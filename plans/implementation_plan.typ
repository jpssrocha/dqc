#import "sbc-template.typ": sbc-template

#show: sbc-template.with(
  title: [Implementation plan for a Data Quality Control System: DQC],
  authors: (
    (name: "João Pedro Rocha", inst: "1"),
    (name: "Antonio Tadeu Gomes", inst: "1"),
  ),
  affiliations: (
    (
      inst: "1",
      text: [Laboratório Nacional de Computação Científica \ Petrópolis - RJ - Brasil],
      email: "{joaor, atagomes}@posgrad.lncc.br",
    ),
  ),
  abstract: [
    Large-scale scientific experiments conducted at multi-user facilities face
    constant risks of acquiring compromised data due to undetected calibration
    drift or instrument degradation during live acquisition. These failures
    cause substantial research delays and waste. This paper presents the
    continuation of the architectural specification with the implementation
    specification, of a decoupled, event-driven real-time Data Quality
    Control (DQC) system.
  ],
)


= Introduction <sec:introduction> // OK
 
Experimental multi-user research facilities, such as optical observatories (LNA)
or synchrotron light sources (LNLS) face constant risks of acquiring unusable
data due to undetected instrument drift during live acquisition runs. In the
first phase of this project, we proposed a real-time, event-driven Data Quality
Control (DQC) architecture. By applying Clean Architecture @martin2017clean
principles and a hybrid architectural style (Broker, Pipe-and-Filter, and
Microkernel), the system decouples raw data acquisition from quality inspection,
enabling non-invasive feedback during ongoing experiments.

In this document, we continue to describe this Data Quality Control system
idealized to run in multi-user experimental facilities, providing a real-time
feedback system so operators and autonomous controllers can optimize live
experiments on-the-fly and prevent costly data loss. We approach it from the
implementation perspective now, as present in @clements2010documenting.

To guide concrete implementations, this system specification starts with three
foundational choices that define our space of possibilities. First, adopting a
Python environment leverages its massive modern scientific tooling ecosystem.
Second, utilizing Apptainer containers provides a containerization technology
tailored specifically toward scientific workloads #footnote[It is the only type
of container technology that targets scientific applications, therefore the only which
makes sense for this project to target], featuring first-class support in queue
systems like Slurm for natural High-Performance Computing (HPC) offloading.
Finally, employing a distributed filesystem and unified storage architecture —
supported by `fsspec` abstractions and object storage like RustFS — facilitates
seamless coordination and data access across heterogeneous hardware nodes, as
well as alleviates the heavy disk I/O introduced as an architectural tradeoff,
by distributing read/write operations across many nodes.

To keep the specification compact, we will be describing here just the
specifications related to the two functional workflows of the system:

+ *Runtime management:* Highlights the deployment view, edge sidecar
  initialization (`WatchFilesDriver`, `DAQEventListener`), session setup in the
  `PipelineOrchestrator`, queue provisioning, event routing, and graceful
  shutdown.

+ *Online job execution:* Highlights the system "stationary state" during
  steady-state frame processing, Apptainer worker provisioning via Python
  `subprocess`, `fsspec` payload staging, and real-time metric streaming via
  the `HookAdapter` abstraction.

#v(0.3cm)

While a complete lifecycle includes container registration and workflow
definition — encompassing static linting, contract verification via the
`ContractValidator`, and manifest persistence within the `ComponentRegistry`
— this pre-execution setup is assumed to be pre-completed to maintain document
brevity and focus on runtime execution. Static registration outputs and verified
container manifests are emulated via pre-configured mock data structures.

The modules detailed in this document, drawn from the module view of the first
paper (Section 3.1), are: `DAQEventListener`, `PipelineOrchestrator`,
`ComponentRegistry`, `ContractValidator`, `HookAdapter`, `ViewPresenter`,
`TaskExecutor`, `ApptainerExecutor`, `FileSystemAdapter`, and the domain
contracts `DataContractSchema`, `EventPayload`, `ModuleManifest`, and
`JobManifest`. Modules deferred to future iterations include `HPCJobOffloader`,
`GenericStreamListener`, and `ViewStreamListener`.

The remainder of this document is organized as follows: @sec:detailed-spec
presents the chosen module specifications, including UML Class Diagrams,
interaction Sequence Diagrams, design pattern applications, and architectural
refinements. @sec:testing outlines the unit and integration test plans.
@sec:final presents final considerations regarding software prototyping and
exequibility.

= Detailed Specification <sec:detailed-spec> // OK
 
This section specifies the two selected workflows: system startup and online
job execution. Each workflow is described with its relevant class and sequence
diagrams.

To reach a functional initial prototype within size limits, a simplification is
adopted: each acquired data file directly triggers and corresponds to exactly
one data quality inspection job. By enforcing a one-to-one mapping between file
creation events and job executions, complex multi-file aggregation patterns and
non-linear directed acyclic graph (DAG) dependencies are intentionally deferred
to future iterations in favor of a clean, waterfall-style processing pipeline.

For the sake of the specified workflows we will assume that the
database in @fig:erd exists, so we don't pollute this document with
administrative tasks that web frameworks (e.g., django) can do out
of the box. As signalled on @fig:erd, processing modules artifacts
(container and manifest) will be represented as strings pointing to its
files on the storage, which for the prototype will be object storage
(using RustFS#footnote[#link("https://rustfs.com/")], an S3 compatible
storage)#footnote[Object storage has some drawbacks for small files,
but is the easiest to setup since no permissions are necessary in
the host machines due to its stateless operations], leveraging the
fsspec#footnote[#link("https://filesystem-spec.readthedocs.io/en/latest/")]
abstraction so a more appropriate type of filesystem can be easily exchanged or
layered afterwards.

#figure(
  image("figures/dqc_erd.drawio.png", height: 25%),
  caption: [ER Diagram of the database assumed to be available for the system],
  placement: auto,
)<fig:erd>

== Registration and Validation <sec:registration> // OK

In this section we describe the modules responsible for registering
user‑submitted processing modules, pipelines, and visualizer schemas. Although
the prototype assumes that these components are already registered and
validated, we specify their interfaces and responsibilities to guide future
implementation. The core classes are `ContractValidator`, `ComponentRegistry`,
and the domain contract `DataContractSchema`. The `ContractValidator` performs
runtime schema enforcement using Pydantic, ensuring that every submitted script
adheres to the expected input/output signature. The `ComponentRegistry` persists
the validated manifests — container images and JSON metadata — in object storage
and indexes them in a relational database. They are depicted as a class diagram
in @fig:validation-modules. A third core class in this layer is `PipelineDef`,
the declarative manifest that results from composing registered modules into
a pipeline.

#figure(
  image("figures/validator_modules.drawio.png", height: 25%),
  caption: [Class diagram for Registration and Validation],
  // placement: auto,
)<fig:validation-modules>

#pagebreak()

== Runtime Management <sec:runtime>

The runtime management workflow covers the lifecycle of a DQC session on the
central gateway. It begins when the edge `DAQEventListener` requests a session
start, passing the project and module identifiers from its `WatcherConfig`.
The `PipelineOrchestrator` then resolves the active pipeline definition from
the `ComponentRegistry`, provisions one Redis queue per processing module, and
prepares the `HookAdapter` and Pub/Sub channels that will carry telemetry to
the live viewers. Once the session is ready, the listener enters passive file
monitoring and forwards each detected `EventPayload` to the orchestrator, which
wraps it into a `JobManifest` — carrying the input file URI, project and module
identifiers, and the downstream queue list — and routes it to the appropriate
module queue. This division keeps the edge adapter thin and makes the
orchestrator the single point of control for queue creation, event routing, and
graceful shutdown. On shutdown, the orchestrator drains the queues, tears down
the hooks, and releases the Redis connections. The runtime sequence is depicted
in the diagram from @fig:runtime-sequence.

#figure(
  image("figures/startup_sequence.drawio.png"),
  caption: [Runtime sequence diagram.],
)<fig:runtime-sequence>

For the prototype, the supporting infrastructure services — Redis for the
RQ#footnote[#link("https://python-rq.org/")] queue and Pub/Sub broker,
and RustFS for object storage — can be readily deployed through a single
`podman-compose` file. Because these services are decoupled from the Apptainer
based execution sandboxes, they can be started, reset, or replaced independently
during development and testing.

The classes involved in this phase are shown below. The `DAQEventListener`
maintains an internal state of the watched directory and a reference to the
`PipelineOrchestrator`. It depends on the `watchfiles` library and the
`EventPayload` data contract. The `PipelineOrchestrator` depends on the
`ComponentRegistry` and the Redis connection.

#figure(
  image("figures/runtime_modules.png"),
  caption: [Class diagram for runtime associated modules],
  placement: auto,
)<fig:runtime-modules>

The runtime design is anchored by a few key patterns. The `PipelineOrchestrator`
acts as a Mediator and Facade, centralizing session setup and exposing only
`start_session` and `shutdown_session` to the rest of the system. The
`EventPayload` and `JobManifest` are like Command objects, encapsulating detected
files and downstream queue names so requests can be queued and executed
independently. The `TaskExecutor` combines Template Method and Strategy, fixing
the execution sequence while allowing interchangeable backends such as
Apptainer or Slurm. The `HookAdapter` applies Adapter and Observer,
translating container output into telemetry and downstream jobs without knowing
the subscribers. The `ComponentRegistry` is a Repository, hiding storage details
behind a collection‑like interface. These patterns preserve the decoupling
promised by the Broker, Pipes‑and‑Filters, and Microkernel styles.

== Job Execution <sec:job-execution>

The job execution workflow represents the steady‑state operation of the system.
A worker process — managed by RQ — picks up a `JobManifest` from the queue
and invokes the `TaskExecutor`. The `TaskExecutor` is an abstract class that
defines the interface for preparing the environment and executing the container.
In the prototype, we provide a concrete implementation using Apptainer that
runs the user‑submitted pipeline inside an isolated sandbox. The input file
is staged into the container using `fsspec` and object storage. Once the
container completes, the `HookAdapter` collects the evaluated metrics from the
output volume and publishes them to a Redis Pub/Sub channel. A `ViewPresenter`
subscribes to this channel and formats the metrics into JSON for the live
dashboard.

#figure(
  image("figures/worker_sequence.drawio.png"),
  caption: [Typical sequence diagram for a worker stage operation.],
  placement: auto,
)

The core classes for this phase are `TaskExecutor`, `ApptainerExecutor`,
`HookAdapter`, `PubSubBroker`, and `ViewPresenter`. The `TaskExecutor` defines
the abstract methods `prepare_environment` and `execute_container`. Its internal
state includes the project name and workload type. The `ApptainerExecutor`
encapsulates the Apptainer invocation, including mounting the input file and
capturing the output. The `HookAdapter` is invoked by the `TaskExecutor` after
the container exits, reads the metrics file produced by the container, and
publishes the parsed metrics to the `PubSubBroker` (and enqueues the downstream
job, when applicable). The `PubSubBroker` is a thin wrapper around Redis
Pub/Sub. The `ViewPresenter` subscribes to the relevant channels and transforms
the raw metrics into a view model suitable for the dashboard. The class diagram
below shows these relationships.

#figure(
  image("figures/worker_modules.drawio.png"),
  caption: [Class diagram for worker related modules.],
  placement: auto,
)

The worker side is anchored by a complementary set of patterns.
`ApptainerExecutor` is a Concrete Strategy fulfilling the execution contract
fixed by `TaskExecutor`, and internally an Adapter translating that contract
into a `subprocess` call to the Apptainer CLI. `FileSystemAdapter` is an
Adapter/Facade over `fsspec`, exposing domain-level staging and collection
operations while hiding the object store. `PubSubBroker` is a classic Broker,
decoupling `HookAdapter` from `ViewPresenter`, and `ViewPresenter` is a
Presenter/Observer reshaping metric payloads into dashboard view models.
`JobManifest` acts as a Command object, letting workers stay stateless and stage
transitions be expressed as plain enqueues. Together with the roles described in
@sec:runtime, these patterns preserve the Broker and Pipes-and-Filters styles at
the execution boundary.

= Testing plan <sec:testing>

Testing is carried out with the pytest framework. To exercise the runtime path
with a concrete workload, the plan adopts a small linear‑fit problem inspired by
common laboratory experiments such as ohmic resistors or Hookean springs. An
apparatus sweeps a controlled variable across N positions, measures a dependent
variable, and writes a CSV with columns `x` and `y`. Stage One fits a linear
model and outputs the angular and linear coefficients as JSON. Stage Two loads
those coefficients, computes the residuals, and performs a normality test,
writing a JSON result. The scenario is small enough to run tests while still
exercising every architectural boundary, from passive file detection to
downstream job enqueueing.

== Unitary Tests <sec:unit-tests>

The unit tests focus on isolated classes and their interfaces. For the
`DAQEventListener`, we simulate file creation events in a temporary directory
and assert that the listener constructs the correct `EventPayload` and forwards
it to the `PipelineOrchestrator` without touching the queue directly. For the
`PipelineOrchestrator`, we mock the `ComponentRegistry` and verify that
`start_session` resolves the pipeline and creates the initial job, and that
`shutdown_session` releases its resources. For the `TaskExecutor`, a dummy
implementation records the order in which `prepare_environment`,
`execute_container`, `collect_outputs`, and `cleanup_environment` are invoked,
confirming that the template method sequence is respected. The
`FileSystemAdapter` is exercised against an in‑memory `fsspec` filesystem to
verify staging, listing, and removal. For the `HookAdapter`, we mock the
`PubSubBroker` and `RedisQueue` and assert that telemetry is published to the
correct channel and that a downstream job is enqueued only when the pipeline is
not terminal. 

== Integration Tests <sec:integration-tests>

The integration tests use the linear‑fit scenario described above. The primary
test starts the `DAQEventListener` on a temporary directory, generates a CSV
using the data generator, and waits for the RQ worker to pick up the first job.
Because the prototype substitutes a dummy `ApptainerExecutor` for the container
runtime, the test verifies the orchestration path rather than sandbox execution:
the `HookAdapter` must publish a telemetry message for the first stage and
enqueue a `JobManifest` for the second, and the same must hold for the second
stage until the pipeline terminates. A second test covers the registration and
validation path using the stubbed `ContractValidator` described in
@sec:registration: a mock script is submitted to the validator, passes static
checks against the stub, and is persisted as a manifest in the mock
`ComponentRegistry`, confirming that the orchestration path from submission to
registered manifest is exercised end to end. A third test attempts to register
a pipeline with a non‑linear DAG and asserts that the prototype rejects it with
a clear error message, confirming that the one‑to‑one simplification is
enforced at registration time. All integration tests share a Redis fixture that
spins up a temporary instance and tears it down at the end of the session.

== Architectural Inadequacies <sec:inadequacies>

The first paper specified the module view in detail, with a class diagram that
placed `PipelineOrchestrator`, `ComponentRegistry`, `ContractValidator`,
`HookAdapter`, and the domain contracts at specific layers. During the detailed
design, five adjustments were made to that class structure. Two are scope
reductions and three are refinements that follow from the runtime model
described in the previous sections.

The first scope reduction concerns pipeline topology. The original
`PipelineOrchestrator` translated declarative manifests into executable DAGs and
controlled stage execution flow. For the prototype we enforce a one-to-one
mapping between file events and jobs and represent the pipeline as a linear
sequence of stages. This removes the need for a central DAG router in the
orchestrator; stage-to-stage transitions are handled by the `HookAdapter`,
which reads the `JobManifest`'s downstream queue list and enqueues the next job
directly. The queues themselves are still provisioned upfront by the
orchestrator at session start.

The second scope reduction concerns the registration services. The original
class diagram placed `ContractValidator` and `ComponentRegistry` as runtime
services in the Application Use Cases layer. For the prototype they are
implemented as lightweight mocks backed by static data, deferring their full
implementation to a later iteration while still allowing the orchestration path
to be exercised end to end. Neither reduction violates the Clean Architecture
layering; they narrow the scope of the first prototype while preserving the
contracts at the center.

The first refinement concerns where the `HookAdapter` is invoked. The original
module view placed the hook in the Interface Adapters layer and described it as
intercepting task lifecycle events and intra-task metric evaluations, with
Flyte cited as an illustrative concrete engine in the outermost layer. The
detailed design keeps the same layering but makes the invocation boundary
explicit: the container is treated as a black box that only reads from and
writes to its mounted volume, and the hook is invoked by the `TaskExecutor`
after the container exits and its outputs have been collected. This preserves
the engine-agnostic position of the adapter — the `TaskExecutor` interface can
be re-implemented for another runtime (e.g., Flyte or a Slurm-native backend)
without changing the hook — while removing the assumption that the sandbox
itself reaches the broker.

The second refinement concerns the data contract. The `DataContractSchema` now
treats `inputs` and `outputs` as optional fields, so a source module such as the
DAQ event has no inputs and a sink module has no outputs, without requiring
special cases in the validator or the orchestrator. A `FileSystemAdapter`
wrapping `fsspec` was also introduced so that object-storage access stays out
of the domain classes and can be faked in tests.

The third refinement concerns the container abstraction. The first paper
described a separate `ContainerSandbox` class alongside a `SandboxDriverAdapter`
port, both intended to keep the sandbox implementation and its filesystem
operations swappable across runtimes. Because the prototype commits to
Apptainer — for its first-class support on scientific HPC platforms — and to
`fsspec` for all filesystem access, this two-layer abstraction became
unnecessary. Sandbox provisioning, input mounting, and output collection now
live directly in the concrete `ApptainerExecutor`, and the `SandboxDriverAdapter`
port is dropped. This is a deliberate simplification: it trades flexibility in
the container runtime for a smaller, more direct code path. If a second
execution backend (e.g., Slurm-native execution) is later introduced, an
equivalent abstraction can be re-introduced at that point without disturbing
the domain contracts.

= Final Remarks <sec:final>

The implementation plan presented here provides a concrete path for building the
first prototype of the DQC system. By focusing on the two critical workflows —
runtime management and online job execution — and by simplifying the pipeline
model to a one‑to‑one file‑to‑job mapping, we enable rapid development while
preserving the essential architectural qualities of non‑invasive integration,
fault isolation, and real‑time feedback. The use of Python, Apptainer, and
Redis aligns with the foundational choices and leverages mature scientific
libraries. The next steps include implementing the `ContractValidator`
and `ComponentRegistry` as real services, supporting multi‑stage DAGs, and
integrating the live dashboard. The test plan ensures that each module and the
overall flow are verified against the requirements. With these foundations, the
DQC system can be deployed in a laboratory setting to provide immediate quality
feedback and prevent costly data loss.

#heading(numbering: none)[LLM Usage]

A Large Language Model was utilized in this text for proofreading and improving
textual flow, structural cohesion, help find adequate terms from the references,
and helping with the initial kick from textual description for standard UML
diagrams through MermaidJS for further edition with DrawIO.


#bibliography("references.bib", style: "chicago-author-date")
