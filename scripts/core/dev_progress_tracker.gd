extends RefCounted

## Tracks verified development milestones across Phases 1-8.
## Never marks an active phase as 100% completed until tested and signed off on device.

enum PhaseStatus {
	PENDING,
	ACTIVE,
	COMPLETED,
}

const ACTIVE_PHASE_NUMBER: int = 3
const ACTIVE_PHASE_PERCENT: int = 85 # Awaiting on-device Phase 3 QA sign-off

var phases: Array[Dictionary] = [
	{
		"id": 1,
		"short": "P1",
		"title": "Foundation, Physics & Controls",
		"status": PhaseStatus.COMPLETED,
		"percent": 100,
	},
	{
		"id": 2,
		"short": "P2",
		"title": "Modular Barmer World & PBR",
		"status": PhaseStatus.COMPLETED,
		"percent": 100,
	},
	{
		"id": 3,
		"short": "P3",
		"title": "Atmosphere, Realism & Optimization",
		"status": PhaseStatus.ACTIVE,
		"percent": ACTIVE_PHASE_PERCENT,
	},
	{
		"id": 4,
		"short": "P4",
		"title": "Vehicle Physics & Traffic",
		"status": PhaseStatus.PENDING,
		"percent": 0,
	},
	{
		"id": 5,
		"short": "P5",
		"title": "NPC Intelligence & Daily Routines",
		"status": PhaseStatus.PENDING,
		"percent": 0,
	},
	{
		"id": 6,
		"short": "P6",
		"title": "112 Emergency & Military Base",
		"status": PhaseStatus.PENDING,
		"percent": 0,
	},
	{
		"id": 7,
		"short": "P7",
		"title": "Original Hero, Shield & Carrier",
		"status": PhaseStatus.PENDING,
		"percent": 0,
	},
	{
		"id": 8,
		"short": "P8",
		"title": "AAA UI, Packaging & Final Polish",
		"status": PhaseStatus.PENDING,
		"percent": 0,
	},
]


func get_active_phase() -> Dictionary:
	for p: Dictionary in phases:
		if int(p["status"]) == PhaseStatus.ACTIVE:
			return p
	return phases[0]


func get_completed_count() -> int:
	var count: int = 0
	for p: Dictionary in phases:
		if int(p["status"]) == PhaseStatus.COMPLETED:
			count += 1
	return count


func get_overall_percent() -> int:
	var total: float = 0.0
	for p: Dictionary in phases:
		total += float(p["percent"])
	return int(roundf(total / float(phases.size())))


func get_completed_labels() -> String:
	var done: PackedStringArray = PackedStringArray()
	for p: Dictionary in phases:
		if int(p["status"]) == PhaseStatus.COMPLETED:
			done.append(String(p["short"]))
	return ", ".join(done) if not done.is_empty() else "NONE"
