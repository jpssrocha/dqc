"""``TaskExecutor`` abstraction (Implementation plan, ``sec:job-execution``).

First-cut of the ``TaskExecutor`` described in the "Job Execution" section and
``sec:runtime``: an abstract class fixing the execution sequence while leaving
the backend swappable (Template Method + Strategy). ``prepare_environment`` and
``execute_container`` are the abstract operations; the concrete
``ApptainerExecutor`` strategy is what the plan expects to fulfil them with an
Apptainer sandbox. ``collect_outputs``/``cleanup_environment`` from the plan
(and ``sec:unit-tests``) are not yet declared here, and the stub
``execute_container`` currently returns ``NotImplemented`` instead of running a
container.
"""

import subprocess
from pathlib import Path

class TaskExecutor:
    """Abstract worker-side execution strategy (see ``sec:job-execution``)."""

    def __init__(self):
        self.project = ""
        self.workload_type = ""

    def prepare_environment(self):
        """Prepare the execution sandbox; implemented by the concrete strategy."""
        raise NotImplementedError

    def execute_container(self, input_file):
        """Execute the processing stage for ``input_file``.

        Placeholder for the ``ApptainerExecutor`` invocation described in
        ``sec:job-execution``; it must eventually mount the staged input and
        capture the produced outputs.
        """
        print("\n\n File is:", input_file, "\n\n")
        return NotImplemented
