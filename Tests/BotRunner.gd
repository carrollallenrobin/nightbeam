"""
Headless bot harness: runs seeds x skills (idle, greedy, careful) with no rendering, checks the invariants
every tick and writes a CSV (seed, skill, result, time_survived, saved, hull, flares_used, score, shade_wrecks, spawns,
spawns_skipped, violations).
Prints the skill-gradient table against the GDD targets. Exit code = number of invariant violations.
Run: godot --headless --path . -s res://Tests/BotRunner.gd -- --seeds=1-100 --out=Tests/Results/bots.csv
Optional: --threads=N (default 4) --skills=idle,greedy --check=0 --tuning=res://Data/Tuning/NightbeamTuning.tres
          --set=spawn_interval_end=0.8,shade_chance_end=0.4   (in-memory overrides for balance sweeps)
"""
extends SceneTree

const NightRunner: GDScript = preload("res://Tests/NightRunner.gd")
const DEFAULT_SEEDS: String = "1-100"
const DEFAULT_OUT: String = "Tests/Results/bots.csv"
## Worker threads for the nights. Each night is independent, so results never depend on it. Measured on
## 4.6.1: 4 threads = 2.4x faster; more threads contend inside the engine and get slower again.
const DEFAULT_THREADS: int = 4
const MAX_THREADS: int = 16
const CSV_HEADER: String = "seed,skill,result,time_survived,saved,hull,flares_used,score,shade_wrecks,spawns,spawns_skipped,violations"


func _init() -> void:
	var args: Dictionary = NightRunner.parse_user_args()
	var tuning_path: String = args.get("tuning", NightbeamSim.DEFAULT_TUNING_PATH)
	var tuning: NightbeamTuning = load(tuning_path) as NightbeamTuning
	if tuning == null:
		printerr("BotRunner: cannot load tuning %s" % tuning_path)
		quit(1)
		return
	if args.has("set"):
		tuning = _with_overrides(tuning, String(args["set"]))
	var seeds: Array[int] = NightRunner.parse_seeds(args.get("seeds", DEFAULT_SEEDS))
	var skills: PackedStringArray = String(args.get("skills", ",".join(NightbeamBots.SKILLS))).split(",", false)
	var check: bool = String(args.get("check", "1")) != "0"
	var out_path: String = _resolve_out(String(args.get("out", DEFAULT_OUT)))
	var started_ms: int = Time.get_ticks_msec()
	var jobs: Array[Dictionary] = []
	for skill: String in skills:
		for s: int in seeds:
			jobs.append({"seed": s, "skill": skill})
	var threads: int = clampi(int(args.get("threads", mini(DEFAULT_THREADS, OS.get_processor_count()))), 1, MAX_THREADS)
	var rows: Array[Dictionary] = _run_jobs(jobs, tuning, check, threads)
	var total_violations: int = 0
	for row: Dictionary in rows:
		total_violations += int(row["violation_count"])
		for v: Dictionary in row["violations"]:
			printerr("INVARIANT seed=%d skill=%s %s: %s" % [row["seed"], row["skill"], v["id"], v["message"]])
	var elapsed_s: float = (Time.get_ticks_msec() - started_ms) / 1000.0
	if not _write_csv(out_path, rows):
		quit(1)
		return
	_print_gradient(rows, skills, tuning.hull_max)
	print("BotRunner: %d runs (%d seeds x %d skills) in %.1f s on %d threads, invariant violations: %d, csv: %s"
		% [rows.size(), seeds.size(), skills.size(), elapsed_s, threads, total_violations, out_path])
	quit(total_violations)


"""
Runs every {seed, skill} job, spread over worker threads. Each night owns its sim and memo and only reads
the shared tuning, so the rows (kept in job order) are identical to a single-threaded run.
"""
func _run_jobs(jobs: Array[Dictionary], tuning: NightbeamTuning, check: bool, threads: int) -> Array[Dictionary]:
	var results: Array = []
	results.resize(jobs.size())
	var mutex: Mutex = Mutex.new()
	var next_job: Array[int] = [0]
	var worker: Callable = func(_worker_index: int) -> void:
		while true:
			mutex.lock()
			var i: int = next_job[0]
			next_job[0] += 1
			mutex.unlock()
			if i >= jobs.size():
				return
			var row: Dictionary = NightRunner.run_night(jobs[i]["seed"], jobs[i]["skill"], tuning, check)
			mutex.lock()
			results[i] = row
			mutex.unlock()
	if threads <= 1:
		worker.call(0)
	else:
		var group: int = WorkerThreadPool.add_group_task(worker, threads, threads, true)
		WorkerThreadPool.wait_for_group_task_completion(group)
	var rows: Array[Dictionary] = []
	for r: Variant in results:
		rows.append(r as Dictionary)
	return rows


"""Returns a copy of tuning with "name=value,name=value" overrides applied (for balance sweeps)."""
func _with_overrides(tuning: NightbeamTuning, spec: String) -> NightbeamTuning:
	var copy: NightbeamTuning = tuning.duplicate() as NightbeamTuning
	for pair: String in spec.split(",", false):
		var kv: PackedStringArray = pair.split("=", false)
		if kv.size() != 2 or not (kv[0] in copy):
			printerr("BotRunner: bad override '%s'" % pair)
			continue
		var current: Variant = copy.get(kv[0])
		copy.set(kv[0], int(kv[1]) if current is int else float(kv[1]))
		print("override %s = %s" % [kv[0], str(copy.get(kv[0]))])
	return copy


func _resolve_out(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	return "res://" + path


func _write_csv(path: String, rows: Array[Dictionary]) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("BotRunner: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_line(CSV_HEADER)
	for r: Dictionary in rows:
		f.store_line("%d,%s,%s,%.3f,%d,%d,%d,%d,%d,%d,%d,%d" % [r["seed"], r["skill"], r["result"], r["time_survived"],
			r["saved"], r["hull"], r["flares_used"], r["score"], r["shade_wrecks"], r["spawns"], r["spawns_skipped"],
			r["violation_count"]])
	f.close()
	return true


func _print_gradient(rows: Array[Dictionary], skills: PackedStringArray, hull_max: int) -> void:
	print("| skill | runs | mean time survived (s) | dawn (win) rate | mean ships saved | mean score | reef hits by shades | mean flares | spawns skipped |")
	print("|---|---|---|---|---|---|---|---|---|")
	var mean_time: Dictionary = {}
	for skill: String in skills:
		var n: int = 0
		var time_sum: float = 0.0
		var wins: int = 0
		var saved_sum: int = 0
		var score_sum: int = 0
		var hits_sum: int = 0
		var shade_hits_sum: int = 0
		var flares_sum: int = 0
		var spawns_sum: int = 0
		var skipped_sum: int = 0
		for r: Dictionary in rows:
			if r["skill"] != skill:
				continue
			n += 1
			time_sum += float(r["time_survived"])
			saved_sum += int(r["saved"])
			score_sum += int(r["score"])
			shade_hits_sum += int(r["shade_wrecks"])
			flares_sum += int(r["flares_used"])
			spawns_sum += int(r["spawns"])
			skipped_sum += int(r["spawns_skipped"])
			hits_sum += hull_max - int(r["hull"])
			if r["result"] == NightbeamSim.state_name(NightbeamSim.State.WON):
				wins += 1
		if n == 0:
			continue
		mean_time[skill] = time_sum / n
		var scheduled: int = maxi(spawns_sum + skipped_sum, 1)
		print("| %s | %d | %.1f | %.0f%% | %.1f | %.0f | %d of %d | %.2f | %d of %d (%.2f%%) |" % [skill, n, time_sum / n,
			100.0 * wins / n, float(saved_sum) / n, float(score_sum) / n, shade_hits_sum, hits_sum,
			float(flares_sum) / n, skipped_sum, scheduled, 100.0 * skipped_sum / scheduled])
	if mean_time.has("careful") and mean_time.has("idle") and mean_time.has("greedy"):
		print("careful/idle survival = %.2fx (target >= 4), careful/greedy = %.2fx (target >= 1.3)" % [
			mean_time["careful"] / maxf(mean_time["idle"], 0.001), mean_time["careful"] / maxf(mean_time["greedy"], 0.001)])
