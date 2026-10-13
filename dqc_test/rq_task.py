"""Dummy RQ workload used to exercise the worker side (``sec:runtime``).

A stand-in for a queued processing job: it burns CPU briefly and returns a
value, letting the RQ/Redis queue described in "Runtime Management" be tested
independently of any Apptainer sandbox. In the real pipeline this position is
occupied by a worker picking a ``JobManifest`` off a module queue and invoking
the ``TaskExecutor`` (``sec:job-execution``).
"""

import time
import random

def hello(someone):
    """Sample job function enqueued by ``rq_test.py``; returns a greeting."""

    res = [random.random() for n in range(20_000_000)]
    res = sum(res)/len(res)

    print(f"hi {someone}")
    return f"hi {someone}"
