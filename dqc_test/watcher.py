"""Runtime management workflow (Implementation plan, ``sec:runtime``).

Spike for the edge side of the session lifecycle described in the
"Runtime Management" section. It plays the roles that the plan assigns to the
edge ``DAQEventListener`` (``watchfiles``-based passive file monitoring), the
``WatcherConfig``/``EventPayload`` data contracts, and the minimal routing that
the ``PipelineOrchestrator`` performs when it wraps a detected file into a
``JobManifest`` and submits it to a module queue.

In this spike the listener and the orchestrator are fused: each detected
``Change.added`` event is routed straight onto an RQ queue (the same Redis/RQ
broker described in ``sec:runtime``) and picked up by a ``TaskExecutor`` worker
(see ``executor_engine.TaskExecutor`` and ``sec:job-execution``). The
``JobManifest``/``WatcherConfig`` dataclasses are first-cut versions of the
domain contracts listed in ``sec:detailed-spec``; queue provisioning and
graceful shutdown are not yet modelled here.
"""

from pathlib import Path
from dataclasses import dataclass

from watchfiles import watch, Change
from redis import Redis
import rq
from rq import Queue
from executor_engine import TaskExecutor


@dataclass
class JobManifest:
    """Command object carrying a detected file to a worker queue.

    Mirrors the ``JobManifest`` contract in ``sec:runtime``/``sec:job-execution``:
    the input file URI, the project and module identifiers, and (once stage
    routing is added) the downstream queue list used by the ``HookAdapter``.
    """

    input_file: str
    output_path: str
    project: str
    container_id: str
 

@dataclass
class WatcherConfig:
    """Edge watcher configuration described in ``sec:runtime``.

    Holds the watched source path plus the project and module identifiers that
    the ``DAQEventListener`` hands to the ``PipelineOrchestrator`` on
    ``start_session``.
    """

    source_path: str
    project_id: str
    module_id: str



def main():
    """Run the fused listener/orchestrator loop for the runtime spike.

    Passive monitoring of ``test_data`` stands in for the listener's
    steady-state file watching in ``sec:runtime``; enqueueing onto the RQ queue
    stands in for the orchestrator's event routing to a module queue.
    """

    DATA_FOLDER = Path("test_data")

    q = Queue(connection=Redis())

    executor = TaskExecutor()


    for event in watch(DATA_FOLDER):
        event_type, file = event.pop()

        if event_type is Change.added:
            # Launch kernel
            print(file)
            q.enqueue(executor.execute_container, file)


if __name__ == "__main__":
    main()

