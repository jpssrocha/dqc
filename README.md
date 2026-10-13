# DQC — Data Quality Control

Early prototype of an event-driven, real-time **Data Quality Control (DQC)**
system for multi-user scientific facilities (e.g. synchrotrons, observatories).
It watches newly acquired apparatus data files, routes each one through a queue
of processing stages (Stage One fits a linear model, Stage Two tests residuals
for normality), and streams metrics to live viewers — so operators can catch
calibration drift or instrument degradation during an ongoing experiment.

The design follows Clean Architecture with a hybrid Broker, Pipe-and-Filter and
Microkernel style. Founding technology choices are Python, Redis (RQ queue +
Pub/Sub), RustFS object storage via `fsspec`, and Apptainer for sandboxed
execution. See the implementation plan for the full architecture.

## Repository layout

- `dqc/` | Intended home of the core runtime package. Currently only empty stubs (`pipeline.py`, `watcher.py`); the working code lives in the spikes under `dqc_test/`. |
- `dqc_modules/` | Separate `uv` workspace package for user-submitted processing modules. `main.py` is the Stage One module: reads the apparatus CSV, fits a line by gradient descent with JAX, and writes output back out. |
- `dqc_test/` | Exploratory spikes implementing the plan's modules and test scenario (see below). |
- `dqc_test/linefit/` | Abandoned Rust scaffold for Stage One, kept only as a record of the exploration. |
- `dqc_test/test_data/` | Place for generated apparatus CSV fixtures (`x`, `y`) used to exercise the pipeline. |

## Root files

- `ficticious_problem.md` — the toy problem driving the prototype: an apparatus
  sweeping a controlled variable and producing `x, y` CSVs to be fit and tested.
- `pyproject.toml` / `uv.lock` / `.python-version` — project metadata and
  dependency lockfile (Python 3.13, `uv` workspace).

