class_name StageLink
extends RefCounted
## Stands a StageTable in the session: its notices go to the room's, and it asks the session
## whether this process is the host and how to put a rope to the host. Kept out of the table
## because a surface must not reach the network (tests: no surface asks what it is looking
## through); the studio and the tests wire a table through here, so both run the same way.


static func wire(table: StageTable) -> void:
	table.told.connect(func(text: String) -> void: Session.notice.emit(text))
	table.hosting = Session.is_authority
	table.asking = Session.ask_room
