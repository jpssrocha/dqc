"""Object-storage event listener spike (``sec:runtime`` / ``sec:detailed-spec``).

Alternative edge listener to the ``watchfiles``-based ``DAQEventListener`` in
``watcher.py``: instead of watching a local directory it subscribes to
``s3:ObjectCreated:*`` notifications on the RustFS bucket, so detected files
arrive as object-storage events. This aligns with the object-storage (RustFS)
and ``fsspec`` choices discussed in ``sec:detailed-spec`` and with the edge
sidecar initialization in "Runtime Management". Each created object is the
equivalent of one ``EventPayload`` to be routed by the ``PipelineOrchestrator``.
"""

import marimo

__generated_with = "0.24.2"
app = marimo.App(width="full")


@app.cell
def _():
    import marimo as mo
    from minio import Minio
    from urllib.parse import unquote_plus

    bucket_name = "experimental-data"
    client = Minio("192.168.0.143:9000", access_key="0RWqeAO4duWM9lQGZyMT", secret_key="lSFkElR6vnkJ3EFcH3g8qGWmIWhzfD3bC8SlArba", secure=False)

    # Direct HTTP event stream — no SQS, Kafka, or webhooks needed
    events = client.listen_bucket_notification(bucket_name, events=["s3:ObjectCreated:*"])
    for event in events:
        print("Created:", unquote_plus(event["Records"][0]["s3"]["object"]["key"]))
    return (event,)


@app.cell
def _(event):
    event
    return


if __name__ == "__main__":
    app.run()
