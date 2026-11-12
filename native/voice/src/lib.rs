//! dawlings' voice: a C ABI over CHIMERA (`vendor/chimera`, MIT) for the rack's VOICE module and
//! the vocal booth's singer. CHIMERA itself is a path dependency on the pinned submodule; its own
//! browser C ABI (`chimera_call`, `engine_*`) is linked into the same archive, so a C caller can
//! use either. These calls exist because the rack is C++ and wants plans as opaque objects rather
//! than JSON and 272-byte records.
//!
//! Threads. A `DvVoice` renders; everything that takes a `DvVoice` and is marked RT here does not
//! allocate, so it may run between or inside audio blocks. Plans (`dv_plan_*`), lyrics
//! (`dv_lyrics_*`) and the dictionary (`dv_init`) allocate: the rack makes them on its planner
//! thread and hands the finished `DvPlan` to the audio side, which only schedules it. A body or
//! creature switch allocates a new airway (CHIMERA's own rule): the rack does it between blocks.
//!
//! Every pointer argument must be a live object from the matching `*_new`/`dv_plan_*` call, and
//! strings must be NUL-terminated UTF-8.

use chimera::anatomy::human::{ArticPatch, BodyMix, HumanFrame, HumanVocalTract, N_ARTIC};
use chimera::control::score::Gesture;
use chimera::creatures::{CREATURES, creature_by_id};
use chimera::engine::{Engine, MAX_SCHEDULE};
use chimera::phonetics::beatbox::{self, BEAT_PRESETS, BEAT_SOUNDS, BeatStep};
use chimera::phonetics::english::EnglishG2P;
use chimera::phonetics::planner::{PhraseInput, PlanOptions, plan_phrases, plan_utterance};
use chimera::phonetics::sing::{LegatoFrom, MelismaOptions, NoteOnOptions, SongOptions, SungNote, midi_to_hz, plan_melisma, plan_note_off, plan_note_on, plan_song};
use chimera::phonetics::syllables::lyrics_to_syllables;
use chimera::phonetics::{Syllable, ipa};
use chimera::voice::human_voice::{SourcePatch, VoiceTelemetry};
use std::ffi::{CStr, c_char};
use std::io::Read;
use std::sync::OnceLock;

// Keep chimera-wasm's exports in the archive (its C ABI is part of what this library ships).
pub use chimera_wasm::api::chimera_call;
pub use chimera_wasm::engine_new;

static G2P: OnceLock<EnglishG2P> = OnceLock::new();

fn g2p() -> &'static EnglishG2P {
    G2P.get_or_init(EnglishG2P::new)
}

fn cstr<'a>(p: *const c_char) -> &'a str {
    if p.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(p) }.to_str().unwrap_or("")
}

fn opt(x: f64) -> Option<f64> {
    if x.is_nan() { None } else { Some(x) }
}

fn body(female: f64, child: f64) -> BodyMix {
    BodyMix::new(female.clamp(0.0, 1.0), child.clamp(0.0, 1.0))
}

/// Load the pronouncing dictionary (CHIMERA's `public/data/cmudict.txt.gz`, gzip) and build the
/// engine's tables. Returns 1 if the dictionary was read; 0 means English falls back to CHIMERA's
/// letter-to-sound rules. Only the first call loads; later calls return whether that one did.
#[unsafe(no_mangle)]
pub extern "C" fn dv_init(cmudict_gz: *const c_char) -> i32 {
    chimera::init();
    let path = cstr(cmudict_gz);
    G2P.get_or_init(|| {
        let mut g = EnglishG2P::new();
        if let Ok(gz) = std::fs::read(path) {
            let mut text = String::new();
            if flate2::read::GzDecoder::new(&gz[..]).read_to_string(&mut text).is_ok() {
                g.load_dict(&text);
                DICT.store(true, std::sync::atomic::Ordering::Relaxed);
            }
        }
        g
    });
    i32::from(DICT.load(std::sync::atomic::Ordering::Relaxed))
}

static DICT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

// ---------------------------------------------------------------- the voice (audio side)

pub struct DvVoice {
    engine: Engine,
    tele: VoiceTelemetry,
    /// a copy of the voice's tract for drawing (`dv_frame`), so drawing never touches the one that sounds
    tract: HumanVocalTract,
    frame: HumanFrame,
}

#[unsafe(no_mangle)]
pub extern "C" fn dv_new(sample_rate: f64) -> *mut DvVoice {
    let engine = Engine::new(sample_rate);
    let tract = engine.voice().airway.tract.clone();
    let mut v = Box::new(DvVoice { engine, tele: VoiceTelemetry::default(), tract, frame: HumanFrame::default() });
    v.engine.telemetry(&mut v.tele); // size the buffers once
    let a = v.engine.voice().artic.x;
    v.tract.compute(&a, &mut v.frame);
    Box::into_raw(v)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_free(v: *mut DvVoice) {
    if !v.is_null() {
        drop(unsafe { Box::from_raw(v) });
    }
}

macro_rules! voice {
    ($v:expr) => {
        unsafe { &mut *$v }
    };
}

/// RT. Render `n` mono samples into `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_render(v: *mut DvVoice, out: *mut f32, n: usize) {
    let out = unsafe { core::slice::from_raw_parts_mut(out, n) };
    voice!(v).engine.render(out);
}

/// RT. The performer's breath, 0..1 (what a key held down or a breath pad gives).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_gate(v: *mut DvVoice, level: f64) {
    voice!(v).engine.set_gate(level.clamp(0.0, 1.0));
}

/// RT. Articulators: `N_ARTIC` (17) values in CHIMERA's ArticKey order (jaw, tbX, tbY, ttX, ttY,
/// ttCurl, root, lipAp, lipProt, lipWidth, labiodental, velum, larynx, epilarynx, ventricular,
/// lateral, dorsum); NaN leaves one as it is.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_artic(v: *mut DvVoice, values: *const f64) {
    let vals = unsafe { core::slice::from_raw_parts(values, N_ARTIC) };
    let mut p = ArticPatch::default();
    for k in 0..N_ARTIC {
        p.values[k] = opt(vals[k]);
    }
    voice!(v).engine.set_artic(&p, None);
}

/// RT. The source: 12 values, NaN unchanged: f0 (Hz), glide, pressure, breathiness, tension,
/// fry, roughness, vibratoDepth, vibratoRate, drift, voiced (0/1), brightness.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_source(v: *mut DvVoice, values: *const f64) {
    let s = unsafe { core::slice::from_raw_parts(values, 12) };
    let p = SourcePatch {
        f0: opt(s[0]),
        glide: opt(s[1]),
        pressure: opt(s[2]),
        breathiness: opt(s[3]),
        tension: opt(s[4]),
        fry: opt(s[5]),
        roughness: opt(s[6]),
        vibrato_depth: opt(s[7]),
        vibrato_rate: opt(s[8]),
        drift: opt(s[9]),
        voiced: opt(s[10]).map(|x| x != 0.0),
        brightness: opt(s[11]),
    };
    voice!(v).engine.set_source(&p);
}

/// RT. The source a sung melody starts from (as `chimera render notes` sets it): the first note's
/// pitch, voiced, lung pressure 9, tension 0.55.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_sing_source(v: *mut DvVoice, midi: f64) {
    voice!(v).engine.set_source(&SourcePatch { f0: Some(midi_to_hz(midi)), voiced: Some(true), pressure: Some(9.0), tension: Some(0.55), ..Default::default() });
}

/// RT. End the open-ended gestures with this tag (a sung note let go).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_release(v: *mut DvVoice, tag: f64) {
    voice!(v).engine.release(tag);
}

/// RT. Drop everything scheduled.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_stop(v: *mut DvVoice) {
    voice!(v).engine.stop_speech();
}

/// RT. The voice clock (s): plans are scheduled against it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_clock(v: *mut DvVoice) -> f64 {
    voice!(v).engine.clock()
}

/// Allocates (a new airway). The body: `female` 0..1, `child` 0..1.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_body(v: *mut DvVoice, female: f64, child: f64) {
    let v = voice!(v);
    v.engine.set_body(body(female, child));
    v.engine.telemetry(&mut v.tele);
    v.tract = v.engine.voice().airway.tract.clone();
}

/// Allocates. Play a creature (its id: songbird, seal, alligator, elephant) instead of the human
/// voice; "" goes back to the human. Returns 1 if it is playing (or the human was asked for).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_creature(v: *mut DvVoice, id: *const c_char) -> i32 {
    let id = cstr(id);
    let v = voice!(v);
    if id.is_empty() {
        v.engine.set_creature(None, &[]);
        return 1;
    }
    match creature_by_id(id) {
        Some(d) => {
            v.engine.set_creature(Some(d), &[]);
            1
        }
        None => 0,
    }
}

/// RT. A creature's param by key, in its own units (see `dv_catalog`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_creature_param(v: *mut DvVoice, key: *const c_char, value: f64) {
    let v = voice!(v);
    let Some(def) = v.engine.creature().map(|c| c.def) else { return };
    if let Some(i) = def.param_index(cstr(key)) {
        v.engine.set_creature_params(&[(i, value)]);
    }
}

/// RT. Play the creature's call `index`; `midi` < 0 keeps its own pitch, else the call's pitch
/// params are scaled to that note.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_call(v: *mut DvVoice, index: usize, midi: f64, amp: f64) {
    let pitch = if midi < 0.0 { None } else { Some(midi_to_hz(midi)) };
    voice!(v).engine.play_call(index, pitch, Some(amp));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_stop_call(v: *mut DvVoice) {
    voice!(v).engine.stop_call();
}

/// RT. Play one beatbox sound (its pattern symbol: B t tss Pf K ^K ! P! kch m) as soon as the
/// mouth can make it; `midi` > 0 pitches a hum. Returns 0 for an unknown sound.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_beat_hit(v: *mut DvVoice, id: *const c_char, midi: f64, accent: f64) -> i32 {
    let id = cstr(id);
    if !BEAT_SOUNDS.iter().any(|s| s.id == id) {
        return 0;
    }
    let mut step = BeatStep::new(id);
    step.note = if midi > 0.0 { Some(midi) } else { None };
    step.accent = opt(accent);
    voice!(v).engine.beat_hit(&step);
    1
}

/// RT. Start or stop the voice's own beat sequencer (its pattern from `dv_beat_apply`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_beat_play(v: *mut DvVoice, playing: i32) {
    voice!(v).engine.set_beat_playing(playing != 0);
}

/// RT. Tempo for the voice's sequencer (NaN keeps).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_beat_tempo(v: *mut DvVoice, bpm: f64, swing: f64) {
    voice!(v).engine.set_beat_tempo(opt(bpm), opt(swing));
}

/// The step under the sequencer's playhead, -1 when stopped.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_beat_step(v: *mut DvVoice) -> i64 {
    voice!(v).engine.beat_step()
}

/// The voice's telemetry into `out` (at most `cap` values); returns how many were written.
/// Header (16): phLen, orLen, velumPort, f0, voicing, pLung, outRms, noiseLevel, noiseNode, gate,
/// clock, nArtic, nPh, nOr, nScope, creature (1 while a creature plays). Then the arrays: artic
/// (nArtic), phAreas (nPh), orAreas (nOr), pressureRms (nPh+nOr), flow (nPh+nOr), glottalArea
/// (nScope). RMS levels are measured since the last call. RT once the voice has rendered.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_telemetry(v: *mut DvVoice, out: *mut f64, cap: usize) -> usize {
    let v = voice!(v);
    v.engine.telemetry(&mut v.tele);
    let t = &v.tele;
    let out = unsafe { core::slice::from_raw_parts_mut(out, cap) };
    let mut n = 0;
    let mut put = |x: f64| {
        if n < cap {
            out[n] = x;
        }
        n += 1;
    };
    let creature = v.engine.creature().is_some();
    for x in [t.ph_len, t.or_len, t.velum_port, t.f0, t.voicing, t.p_lung, t.out_rms, t.noise_level, t.noise_node as f64, t.gate, t.clock] {
        put(x);
    }
    for x in [t.artic.len(), t.ph_areas.len(), t.or_areas.len(), t.glottal_area.len()] {
        put(x as f64);
    }
    put(if creature { 1.0 } else { 0.0 });
    for arr in [&t.artic, &t.ph_areas, &t.or_areas, &t.pressure_rms, &t.flow, &t.glottal_area] {
        for x in arr.iter() {
            put(*x as f64);
        }
    }
    n.min(cap)
}

// ---------------------------------------------------------------- lyrics (planner side)

/// The song's words as sung syllables, one per note.
pub struct DvLyrics {
    syl: Vec<Syllable>,
}

/// Allocates. English lyrics (CMUdict, then letter-to-sound) into syllables. `ipa` != 0 reads
/// the text as IPA instead, one syllable per space-separated chunk.
#[unsafe(no_mangle)]
pub extern "C" fn dv_lyrics_new(text: *const c_char, ipa_text: i32) -> *mut DvLyrics {
    let text = cstr(text);
    let syl = if ipa_text != 0 {
        text.split_whitespace().filter_map(ipa_syllable).collect()
    } else {
        lyrics_to_syllables(text, g2p())
    };
    Box::into_raw(Box::new(DvLyrics { syl }))
}

/// One IPA chunk as a syllable: consonants before the first vowel are its onset, the first vowel
/// its nucleus, the rest its coda.
fn ipa_syllable(chunk: &str) -> Option<Syllable> {
    let segs = ipa::tokenize_ipa(chunk);
    let body = BodyMix::MALE;
    let vi = segs.iter().position(|s| chimera::phonetics::planner::is_vowel(&s.ipa, body))?;
    Some(Syllable { text: chunk.to_string(), onset: segs[..vi].to_vec(), nucleus: segs[vi].clone(), coda: segs[vi + 1..].to_vec(), melisma: None, word_end: true, ..Default::default() })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_lyrics_free(l: *mut DvLyrics) {
    if !l.is_null() {
        drop(unsafe { Box::from_raw(l) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_lyrics_len(l: *const DvLyrics) -> usize {
    if l.is_null() { 0 } else { unsafe { &*l }.syl.len() }
}

/// Syllable `i`'s text into `buf` (NUL-terminated, cut to `cap`); returns its full length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_lyrics_text(l: *const DvLyrics, i: usize, buf: *mut u8, cap: usize) -> usize {
    let s = unsafe { &*l }.syl.get(i).map_or("", |s| s.text.as_str());
    write_str(s, buf, cap)
}

fn write_str(s: &str, buf: *mut u8, cap: usize) -> usize {
    if cap > 0 && !buf.is_null() {
        let b = unsafe { core::slice::from_raw_parts_mut(buf, cap) };
        let mut n = s.len().min(cap - 1);
        while !s.is_char_boundary(n) {
            n -= 1;
        }
        b[..n].copy_from_slice(&s.as_bytes()[..n]);
        b[n] = 0;
    }
    s.len()
}

fn syl_at(l: *const DvLyrics, i: i64) -> Syllable {
    let l = unsafe { l.as_ref() };
    match l {
        Some(l) if !l.syl.is_empty() => l.syl[(i.rem_euclid(l.syl.len() as i64)) as usize].clone(),
        // no lyrics: an open "ah"
        _ => ipa_syllable("ɑ").unwrap(),
    }
}

// ---------------------------------------------------------------- plans (planner side)

/// Gestures to schedule, planned with times relative to "now"; or a beat pattern.
pub struct DvPlan {
    gestures: Vec<Gesture>,
    end: f64,
    beat: Option<(Vec<Option<BeatStep>>, f64, f64)>,
}

fn plan(gestures: Vec<Gesture>, end: f64) -> *mut DvPlan {
    Box::into_raw(Box::new(DvPlan { gestures, end, beat: None }))
}

/// Allocates. A key pressed: syllable `idx` (wrapping) of `l` at `midi`, its vowel held until
/// `dv_release(tag)` (and `tag + 1`). `legato_idx` >= 0 sings that syllable's tail first.
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_note_on(l: *const DvLyrics, idx: i64, midi: f64, female: f64, child: f64, vibrato: f64, tag: f64, legato_idx: i64, legato_midi: f64) -> *mut DvPlan {
    let syl = syl_at(l, idx);
    let legato_from = if legato_idx >= 0 { Some(LegatoFrom { syl: syl_at(l, legato_idx), midi: legato_midi }) } else { None };
    let g = plan_note_on(&syl, midi, &NoteOnOptions { body: body(female, child), vibrato, tag, legato_from });
    plan(g, 0.0)
}

/// Allocates. A key let go: syllable `idx`'s glide and coda (release its tags first).
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_note_off(l: *const DvLyrics, idx: i64, midi: f64, female: f64, child: f64) -> *mut DvPlan {
    plan(plan_note_off(&syl_at(l, idx), midi, body(female, child)), 0.0)
}

/// Allocates. The held vowel moves to `midi` (release `tag + 1` first).
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_melisma(midi: f64, vibrato: f64, tag: f64) -> *mut DvPlan {
    plan(plan_melisma(midi, &MelismaOptions { vibrato, tag }), 0.0)
}

/// Allocates. A melody: `n` pairs (midi, beats) in `notes`, a midi <= 0 being a rest that ends a
/// phrase (each phrase is planned with its own breath, as `chimera render notes` does). Sounding
/// notes take syllables of `l` from `first` on. The first note's beat is at plan time `t0`
/// (its onset consonants come before it, so they land ahead of the beat).
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_song(l: *const DvLyrics, first: i64, notes: *const f64, n: usize, bpm: f64, t0: f64, vibrato: f64, female: f64, child: f64) -> *mut DvPlan {
    let raw = unsafe { core::slice::from_raw_parts(notes, n * 2) };
    let b = body(female, child);
    let beat = 60.0 / bpm;
    let mut gestures = Vec::new();
    let (mut t, mut k, mut end) = (t0, first, 0.0f64);
    let mut phrase: Vec<SungNote> = Vec::new();
    let mut start = t;
    let flush = |phrase: &mut Vec<SungNote>, start: f64, gestures: &mut Vec<Gesture>, end: &mut f64| {
        if phrase.is_empty() {
            return;
        }
        let p = plan_song(phrase, &SongOptions { body: b, bpm, t0: start, vibrato });
        gestures.extend_from_slice(&p.gestures);
        if p.end > *end {
            *end = p.end;
        }
        phrase.clear();
    };
    for i in 0..n {
        let (midi, beats) = (raw[2 * i], raw[2 * i + 1]);
        if midi > 0.0 {
            if phrase.is_empty() {
                start = t;
            }
            phrase.push(SungNote { midi, beats, syl: syl_at(l, k) });
            k += 1;
        } else {
            flush(&mut phrase, start, &mut gestures, &mut end);
        }
        t += beats * beat;
    }
    flush(&mut phrase, start, &mut gestures, &mut end);
    plan(gestures, end)
}

/// Allocates. Speak `text`: English (as `chimera render text` says it: the phrase planner from
/// 50 ms, the body's speaking pitch) or, with `ipa` != 0, IPA as one utterance.
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_say(text: *const c_char, ipa_text: i32, female: f64, child: f64) -> *mut DvPlan {
    let text = cstr(text);
    let b = body(female, child);
    // the CLI's speaking pitches, blended by the body
    let f0 = 112.0 * (1.0 - b.female - b.child).max(0.0) + 205.0 * b.female + 250.0 * b.child;
    let o = PlanOptions { body: b, t0: 0.05, f0: Some(f0), ..Default::default() };
    let p = if ipa_text != 0 {
        plan_utterance(&ipa::tokenize_ipa(text), &o)
    } else {
        let inputs: Vec<PhraseInput> = g2p().to_phrases(text).into_iter().map(|p| PhraseInput { segments: p.segments, intonation: Some(p.intonation), pause: Some(p.pause) }).collect();
        plan_phrases(&inputs, &o)
    };
    plan(p.gestures, p.end)
}

/// Allocates. A beat pattern in CHIMERA's notation ("B . t . | Pf . t ."), or a preset's name.
#[unsafe(no_mangle)]
pub extern "C" fn dv_plan_beat(text: *const c_char, bpm: f64, swing: f64) -> *mut DvPlan {
    let text = cstr(text);
    let (src, bpm0, swing0) = match BEAT_PRESETS.iter().find(|p| p.name.eq_ignore_ascii_case(text)) {
        Some(p) => (p.text, p.bpm, p.swing),
        None => (text, 96.0, 0.0),
    };
    let steps = beatbox::parse_beat(src);
    let bpm = if bpm > 0.0 { bpm } else { bpm0 };
    let swing = if swing >= 0.0 { swing } else { swing0 };
    Box::into_raw(Box::new(DvPlan { gestures: Vec::new(), end: 0.0, beat: Some((steps, bpm, swing)) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_plan_end(p: *const DvPlan) -> f64 {
    unsafe { &*p }.end
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_plan_len(p: *const DvPlan) -> usize {
    let p = unsafe { &*p };
    p.beat.as_ref().map_or(p.gestures.len(), |b| b.0.len())
}

/// RT. Schedule a plan on the voice, its time 0 at now + `lead` seconds; `replace` drops what was
/// scheduled first. A beat plan sets the voice's sequencer pattern and tempo instead. Returns the
/// voice-clock time of the plan's 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_schedule(v: *mut DvVoice, p: *const DvPlan, lead: f64, replace: i32) -> f64 {
    let v = voice!(v);
    let p = unsafe { &*p };
    if let Some((steps, bpm, swing)) = &p.beat {
        v.engine.set_beat_steps(steps);
        v.engine.set_beat_tempo(Some(*bpm), Some(*swing));
        return v.engine.clock();
    }
    let mut off = v.engine.clock() + lead;
    let mut first = true;
    for chunk in p.gestures.chunks(MAX_SCHEDULE) {
        off = v.engine.schedule(chunk, lead, first && replace != 0);
        first = false;
    }
    if p.gestures.is_empty() && replace != 0 {
        v.engine.stop_speech();
    }
    off
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_plan_free(p: *mut DvPlan) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(p) });
    }
}

// ---------------------------------------------------------------- what there is

/// The catalogue as JSON into `buf` (cut to `cap`, NUL-terminated); returns its full length.
/// {"artic": [names], "beatSounds": [{id, name, role, hint}], "beatPresets": [{name, bpm, swing,
/// text}], "creatures": [{id, name, blurb, role, params: [{key, label, min, max, default}],
/// calls: [{id, name, hint}]}]}
#[unsafe(no_mangle)]
pub extern "C" fn dv_catalog(buf: *mut u8, cap: usize) -> usize {
    use serde_json::json;
    chimera::init();
    let j = json!({
        "artic": chimera::anatomy::human::ArticKey::NAMES,
        "beatSounds": BEAT_SOUNDS.iter().map(|s| json!({"id": s.id, "name": s.name, "role": format!("{:?}", s.role), "hint": s.hint})).collect::<Vec<_>>(),
        "beatPresets": BEAT_PRESETS.iter().map(|p| json!({"name": p.name, "bpm": p.bpm, "swing": p.swing, "text": p.text})).collect::<Vec<_>>(),
        "creatures": CREATURES.iter().map(|c| json!({
            "id": c.id, "name": c.name, "blurb": c.blurb, "role": c.role,
            "params": c.params.iter().map(|p| json!({"key": p.key, "label": p.label, "min": p.min, "max": p.max, "default": p.default})).collect::<Vec<_>>(),
            "calls": c.calls.iter().map(|k| json!({"id": k.id, "name": k.name, "hint": k.hint})).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
    });
    write_str(&j.to_string(), buf, cap)
}

/// A calibrated vowel's articulators (IPA: i ɪ e ɛ æ a ɑ ɒ ɔ o ʊ u ʌ ə ɐ ɝ y ø œ ɨ ɯ ɤ), blended by
/// the body's weights, into `out` (N_ARTIC values, NaN where the vowel leaves one free). Returns 0
/// for a vowel the table does not have. Allocation-free once the table is loaded (`dv_init`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_vowel(ipa_vowel: *const c_char, female: f64, child: f64, out: *mut f64) -> i32 {
    let out = unsafe { core::slice::from_raw_parts_mut(out, N_ARTIC) };
    let name = cstr(ipa_vowel);
    let table = chimera::phonetics::planner::vowel_table();
    out.fill(f64::NAN);
    let mut found = false;
    for (b, w) in body(female, child).weights() {
        if w <= 0.0 {
            continue;
        }
        let Some(t) = table.get(b.as_str()).and_then(|m| m.get(name)) else { continue };
        found = true;
        for k in 0..N_ARTIC {
            if let Some(x) = t.artic.values[k] {
                out[k] = if out[k].is_nan() { x * w } else { out[k] + x * w };
            }
        }
    }
    i32::from(found)
}

/// The articulators' ranges into `lo`, `hi` and `rest` (N_ARTIC each), for a hand or a CV that
/// moves one across its whole travel.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_artic_range(lo: *mut f64, hi: *mut f64, rest: *mut f64) {
    use chimera::control::articulators::ARTIC_SPECS;
    let (lo, hi, rest) = unsafe { (core::slice::from_raw_parts_mut(lo, N_ARTIC), core::slice::from_raw_parts_mut(hi, N_ARTIC), core::slice::from_raw_parts_mut(rest, N_ARTIC)) };
    let n = chimera::anatomy::human::NEUTRAL;
    for k in 0..N_ARTIC {
        lo[k] = ARTIC_SPECS[k].min;
        hi[k] = ARTIC_SPECS[k].max;
        rest[k] = n.to_array()[k];
    }
}

/// The head's outlines now (CHIMERA's own drawing geometry, cm, y up), at most `per` points each, into `out`
/// (at most `cap` values); returns how many were written. Layout: glottis x, y, then 11 outlines in this order,
/// each its point count then x, y pairs: outer wall, inner wall, tongue, velum, upper lip, lower lip, upper
/// teeth, lower teeth, jaw bone, epiglottis, nasal cavity. Reuses its buffers (no allocation once sized).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn dv_frame(v: *mut DvVoice, out: *mut f64, cap: usize, per: usize) -> usize {
    let v = voice!(v);
    let a = v.engine.voice().artic.x;
    v.tract.compute(&a, &mut v.frame);
    let f = &v.frame;
    let out = unsafe { core::slice::from_raw_parts_mut(out, cap) };
    let mut n = 0;
    let mut put = |x: f64| {
        if n < cap {
            out[n] = x;
        }
        n += 1;
    };
    put(f.glottis.x);
    put(f.glottis.y);
    let per = per.max(2);
    for line in [&f.outer, &f.inner, &f.tongue, &f.velum, &f.upper_lip, &f.lower_lip, &f.upper_teeth, &f.lower_teeth, &f.jaw_bone, &f.epiglottis, &f.nasal_cavity] {
        let m = line.len();
        let k = m.min(per);
        put(k as f64);
        for i in 0..k {
            // evenly through the line, both ends kept
            let j = if k <= 1 { 0 } else { i * (m - 1) / (k - 1) };
            put(line[j].x);
            put(line[j].y);
        }
    }
    n.min(cap)
}
