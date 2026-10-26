package engine

import "core:sync"
import "core:thread"

// ============================================================================
// Background tessellation of vector assets (Phase 14 V.4).
//
// Zooming past a scale bucket needs a new mesh for every asset on screen -
// 0.2-1 ms each, a hitch with dozens of different characters. Instead the
// asset keeps drawing its nearest cached mesh (slightly soft for a frame or
// two) while a worker tessellates the new bucket; the main thread installs
// finished meshes (Vector_JobPump, once per frame) and uploads them when
// next drawn. An asset without any mesh yet is tessellated at once.
//
// Ownership: a job holds a reference to its resource (a release can't free
// the document under a worker), and a resource with jobs running isn't
// reloaded (the next check does it); a job whose resource changed version
// meanwhile is dropped. Workers have their own scratch buffers and clear
// their thread's temp allocator. The web build has no threads: there the
// tessellation is synchronous.
// ============================================================================

VECTOR_THREADS :: 2

Vector_Job :: struct {
	res:     ^Vector_Resource,
	bucket:  f32,
	version: int,
	mesh:    Vector_Mesh, // the result (heap; moved into the cache)
}

@(private = "file")
vjobs: struct {
	pool:    thread.Pool,
	started: bool,
	webDone: [dynamic]^Vector_Job, // (web: done at once)
	running: int,
}

// Vector_JobsRunning: tessellations in flight (tests, the profiler).
Vector_JobsRunning :: proc() -> int {return vjobs.running}

// vector_job_submit queues a bucket of a resource for tessellation.
vector_job_submit :: proc(r: ^Vector_Resource, bucket: f32) {
	a := Engine_HeapAllocator()
	if !vjobs.started {
		when ODIN_OS != .JS {
			thread.pool_init(&vjobs.pool, a, VECTOR_THREADS)
			thread.pool_start(&vjobs.pool)
		}
		vjobs.started = true
	}
	j := new(Vector_Job, a)
	j.res, j.bucket, j.version = r, bucket, r.version
	r.refs += 1 // (the job's)
	r.pending += 1
	vjobs.running += 1
	when ODIN_OS == .JS {
		vector_task({data = j})
		if vjobs.webDone == nil do vjobs.webDone = make([dynamic]^Vector_Job, a)
		append(&vjobs.webDone, j)
	} else {
		thread.pool_add_task(&vjobs.pool, a, vector_task, j)
	}
}

// vector_task (worker): the document -> a mesh. Reads the document (frozen
// while jobs run), writes only its job.
@(private = "file")
vector_task :: proc(t: thread.Task) {
	context.allocator = Engine_HeapAllocator()
	j := cast(^Vector_Job)t.data
	tess: Vector_Tess
	Vector_Tessellate(&tess, j.res.doc.shapes[:], j.bucket, &j.mesh)
	Vector_Tess_Destroy(&tess)
	free_all(context.temp_allocator)
	sync.atomic_thread_fence(.Release)
}

// Vector_JobPump installs finished meshes (main thread, once per frame).
Vector_JobPump :: proc() {
	if !vjobs.started do return
	for {
		j: ^Vector_Job
		when ODIN_OS == .JS {
			if len(vjobs.webDone) == 0 do break
			j = pop_front(&vjobs.webDone)
		} else {
			task, ok := thread.pool_pop_done(&vjobs.pool)
			if !ok do break
			sync.atomic_thread_fence(.Acquire)
			j = cast(^Vector_Job)task.data
		}
		vector_job_finish(j)
	}
}

@(private = "file")
vector_job_finish :: proc(j: ^Vector_Job) {
	context.allocator = Engine_HeapAllocator()
	r := j.res
	vjobs.running -= 1
	r.pending -= 1
	if j.version == r.version {
		vector_resource_install(r, j.bucket, &j.mesh)
	} else {
		Vector_Mesh_Destroy(&j.mesh)
	}
	ResourceManager_ReleaseVector(r) // (the job's reference; may free it)
	free(j)
}

// Vector_JobsShutdown waits for the workers and installs / drops their
// results (game end, before resources are freed).
Vector_JobsShutdown :: proc() {
	if !vjobs.started do return
	when ODIN_OS != .JS do thread.pool_join(&vjobs.pool)
	Vector_JobPump()
	delete(vjobs.webDone)
	when ODIN_OS != .JS do thread.pool_destroy(&vjobs.pool)
	vjobs = {}
}
