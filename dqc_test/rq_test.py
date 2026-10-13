"""RQ queue dispatch check (``sec:runtime`` / ``sec:integration-tests``).

Minimal harness for the Redis + RQ broker used for queue provisioning and
event routing in "Runtime Management": it enqueues several dummy jobs and waits
for the workers to finish, verifying that jobs are picked up and their results
retrievable. The integration tests of ``sec:integration-tests`` extend this
with a Redis fixture and the actual stage-one/stage-two ``JobManifest`` flow.
"""

from redis import Redis
from rq import Queue
from rq_task import hello
import time
    

q = Queue(connection=Redis())

jobs = [q.enqueue(hello, f"rq_{i}") for i in range(8)]

while not all([job.is_finished for job in jobs]):
    for j in jobs:
        j.refresh()

    time.sleep(0.1)

for j in jobs:
    print(j.result)

