"""RustFS/fsspec staging spike (``sec:job-execution`` / ``sec:detailed-spec``).

Exercises the object-storage access path taken by the ``FileSystemAdapter``:
using ``fsspec`` (the ``s3fs`` backend) to upload a generated apparatus CSV
into the RustFS bucket. This is the payload-staging step performed before a
container runs in "Job Execution", and the ``fsspec`` abstraction that the plan
adopts to keep object-storage details out of the domain classes. Credentials
below are local-development values for the RustFS endpoint.
"""

import marimo

__generated_with = "0.24.2"
app = marimo.App(width="full")


@app.cell
def _():
    import marimo as mo
    import fsspec


    return (fsspec,)


@app.cell
def _(fsspec):
    # Configure credentials and your local network RustFS endpoint
    storage_options = {
        "key": "0RWqeAO4duWM9lQGZyMT",
        "secret": "lSFkElR6vnkJ3EFcH3g8qGWmIWhzfD3bC8SlArba",
        "client_kwargs": {
            "endpoint_url": "http://192.168.0.143:9000"  # RustFS IP and port
        }
    }

    # Initialize the filesystem client
    fs = fsspec.filesystem("s3", **storage_options)

    bucket_name = "experimental-data"
    local_path = f"./dqc_test/test_data/linear_2026-09-27_22:10:43.263087.csv"
    remote_path = f"s3://{bucket_name}/runs/{local_path.split('/')[-1]}"

    # Ensure the bucket exists
    if not fs.exists(bucket_name):
        fs.mkdir(bucket_name)

    # 1. Upload (Copy) local file to RustFS
    fs.put(local_path, remote_path)

    # 2. To strictly "Move" (Upload then delete local original)
    # fs.put(local_path, remote_path)
    # import os; os.remove(local_path)
    return


@app.cell
def _():
    return


if __name__ == "__main__":
    app.run()
