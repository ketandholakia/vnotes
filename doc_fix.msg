docs: remove tray submenu from Phase 4B scope

The "Recently modified" tray submenu proposed for Phase 4B would require
reviving TTrayController, contradicting the Phase 2 dead-code decision.

Moved to Phase 4D, to be addressed after the TTrayController removal
decision.

Phase 4B is now strictly: note list form + in-memory search + Ctrl+Alt+F wiring.
