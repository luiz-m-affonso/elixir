defmodule Application do
  @moduledoc """
  A module for working with applications and defining application callbacks.

  Applications are the idiomatic way to package software in Erlang/OTP. To get
  the idea, they are similar to the "library" concept common in other
  programming languages, but with some additional characteristics.

  An application is a component implementing some specific functionality, with a
  standardized directory structure, configuration, and lifecycle. Applications
  are *loaded*, *started*, and *stopped*.

  ## The application resource file

  Applications are specified in their [*resource
  file*](http://erlang.org/doc/man/app.html), which is a file called `APP.app`,
  where `APP` is the application name. For example, the application resource
  file of the OTP application `ex_unit` is called `ex_unit.app`.

  You'll find the resource file of an application in its `ebin` directory, it is
  generated automatically by Mix. Some of its keys are taken from the keyword
  lists returned by the `project/0` and `application/0` functions defined in
  `mix.exs`, and others are generated by Mix itself.

  You can learn more about the generation of application resource files in the
  documentation of `Mix.Tasks.Compile.App`, available as well by running `mix
  help compile.app`.

  ## The application environment

  The key `env` of an application resource file has a list of tuples that map
  atoms to terms, and its contents are known as the application *environment*.
  Note that this environment is unrelated to the operating system environment.

  By default, the environment of an application is an empty list. In a Mix
  project you can set that key in `application/0`:

      def application do
        [env: [redis_host: "localhost"]]
      end

  and the generated application resource file is going to have it included.

  The environment is available after loading the application, which is a process
  explained later:

      Application.load(:APP_NAME)
      #=> :ok

      Application.get_env(:APP_NAME, :redis_host)
      #=> "localhost"

  In Mix projects, the environment of the application and its dependencies can
  be overridden via the `config/config.exs` file. If you start the application
  with Mix, that configuration is available at compile time, and at runtime too,
  but take into account it is not included in the generated application resource
  file, and it is not available if you start the application without Mix.

  For example, someone using your application can override its `:redis_host`
  environment variable as follows:

      config :APP_NAME, redis_host: "redis.local"

  The function `put_env/3` allows dynamic configuration of the application
  environment, but as a rule of thumb each application is responsible for its
  own environment. Please do not use the functions in this module for directly
  accessing or modifying the environment of other applications.

  The application environment can be overridden via the `-config` option of
  `erl`, as well as command-line flags, as we are going to see below.

  ## The application callback module

  The `mod` key of an application resource file configures an application
  callback module and start argument:

      def application do
        [mod: {MyApp, []}]
      end

  This key is optional, only needed for applications that start a supervision tree.

  The `MyApp` module given to `:mod` needs to implement the `Application` behaviour.
  This can be done by putting `use Application` in that module and implementing the
  `c:start/2` callback, for example:

      defmodule MyApp do
        use Application

        def start(_type, _args) do
          children = []
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  The `c:start/2` callback has to spawn and link a supervisor and return `{:ok,
  pid}` or `{:ok, pid, state}`, where `pid` is the PID of the supervisor, and
  `state` is an optional application state. `args` is the second element of the
  tuple given to the `:mod` option.

  The `type` argument passed to `c:start/2` is usually `:normal` unless in a
  distributed setup where application takeovers and failovers are configured.
  Distributed applications are beyond the scope of this documentation.

  When an application is shutting down, its `c:stop/1` callback is called after
  the supervision tree has been stopped by the runtime. This callback allows the
  application to do any final cleanup. The argument is the state returned by
  `c:start/2`, if it did, or `[]` otherwise. The return value of `c:stop/1` is
  ignored.

  By using `Application`, modules get a default implementation of `c:stop/1`
  that ignores its argument and returns `:ok`, but it can be overridden.

  Application callback modules may also implement the optional callback
  `c:prep_stop/1`. If present, `c:prep_stop/1` is invoked before the supervision
  tree is terminated. Its argument is the state returned by `c:start/2`, if it did,
  or `[]` otherwise, and its return value is passed to `c:stop/1`.

  ## The application lifecycle

  ### Loading applications

  Applications are *loaded*, which means that the runtime finds and processes
  their resource files:

      Application.load(:ex_unit)
      #=> :ok

  If an application has included applications, they are also loaded. And the
  procedure recurses if they in turn have included applications. Included
  applications are unrelated to applications in Mix umbrella projects, they are
  an Erlang/OTP concept that has to do with coordinated starts.

  When an application is loaded, the environment specified in its resource file
  is merged with any overrides from config files passed to `erl` via the
  `-config` option. It is worth highlighting that releases pass `sys.config`
  this way. The resulting environment can still be overridden again via specific
  `-Application` flags passed to `erl`.

  Loading an application *does not* load its modules.

  In practice, you rarely load applications by hand because that is part of the
  start process, explained next.

  ### Starting applications

  Applications are also *started*:

      Application.start(:ex_unit)
      #=> :ok

  Once your application is compiled, running your system is a matter of starting
  your current application and its dependencies. Differently from other languages,
  Elixir does not have a `main` procedure that is responsible for starting your
  system. Instead, you start one or more applications, each with their own
  initialization and termination logic.

  When an application is started, the runtime loads it if it hasn't been loaded
  yet (in the technical sense described above). Then, it checks if the
  dependencies listed in the `applications` key of the resource file are already
  started. Having at least one dependency not started is an error condition, but
  when you start an application with `mix run`, Mix takes care of starting all
  the dependencies for you, so in practice you don't need to worry about it
  unless you are starting applications manually with the API provided by this
  module.

  If the application does not have a callback module configured, starting is
  done at this point. Otherwise, its `c:start/2` callback if invoked. The PID of
  the top-level supervisor returned by this function is stored by the runtime
  for later use, and the returned application state is saved too, if any.

  ### Stopping applications

  Started applications are, finally, *stopped*:

      Application.stop(:ex_unit)
      #=> :ok

  Stopping an application without a callback module is defined, but except for
  some system tracing, it is in practice a no-op.

  Stopping an application with a callback module has three steps:

  1. If present, invoke the optional callback `c:prep_stop/1`.
  2. Terminate the top-level supervisor.
  3. Invoke the required callback `c:stop/1`.

  The arguments passed to the callbacks are related to the state optionally
  returned by `c:start/2`, and are documented in the section about the callback
  module above.

  It is important to highlight that step 2 is a blocking one. Termination of a
  supervisor triggers a recursive chain of children terminations, therefore
  orderly shutting down all descendant processes. The `c:stop/1` callback is
  invoked only after termination of the whole supervision tree.

  Shutting down a live system cleanly can be done by calling `System.stop/1`. It
  will shut down every application in the opposite order they had been started.

  By default, a SIGTERM from the operating system will automatically translate to
  `System.stop/0`. You can also have more explicit control over OS signals via the
  `:os.set_signal/2` function.

  ## Tooling

  The Mix build tool can also be used to start your applications. For example,
  `mix test` automatically starts your application dependencies and your application
  itself before your test runs. `mix run --no-halt` boots your current project and
  can be used to start a long running system. See `mix help run`.

  Developers can also use tools like [Distillery](https://github.com/bitwalker/distillery)
  that build **releases**. Releases are able to package all of your source code
  as well as the Erlang VM into a single directory. Releases also give you explicit
  control over how each application is started and in which order. They also provide
  a more streamlined mechanism for starting and stopping systems, debugging, logging,
  as well as system monitoring.

  Finally, Elixir provides tools such as escripts and archives, which are
  different mechanisms for packaging your application. Those are typically used
  when tools must be shared between developers and not as deployment options.
  See `mix help archive.build` and `mix help escript.build` for more detail.

  ## Further information

  For further details on applications please check the documentation of the
  [`application`](http://www.erlang.org/doc/man/application.html) Erlang module,
  and the
  [Applications](http://www.erlang.org/doc/design_principles/applications.html)
  section of the [OTP Design Principles User's
  Guide](http://erlang.org/doc/design_principles/users_guide.html).
  """

  @doc """
  Called when an application is started.

  This function is called when an application is started using
  `Application.start/2` (and functions on top of that, such as
  `Application.ensure_started/2`). This function should start the top-level
  process of the application (which should be the top supervisor of the
  application's supervision tree if the application follows the OTP design
  principles around supervision).

  `start_type` defines how the application is started:

    * `:normal` - used if the startup is a normal startup or if the application
      is distributed and is started on the current node because of a failover
      from another node and the application specification key `:start_phases`
      is `:undefined`.
    * `{:takeover, node}` - used if the application is distributed and is
      started on the current node because of a failover on the node `node`.
    * `{:failover, node}` - used if the application is distributed and is
      started on the current node because of a failover on node `node`, and the
      application specification key `:start_phases` is not `:undefined`.

  `start_args` are the arguments passed to the application in the `:mod`
  specification key (e.g., `mod: {MyApp, [:my_args]}`).

  This function should either return `{:ok, pid}` or `{:ok, pid, state}` if
  startup is successful. `pid` should be the PID of the top supervisor. `state`
  can be an arbitrary term, and if omitted will default to `[]`; if the
  application is later stopped, `state` is passed to the `stop/1` callback (see
  the documentation for the `c:stop/1` callback for more information).

  `use Application` provides no default implementation for the `start/2`
  callback.
  """
  @callback start(start_type, start_args :: term) ::
              {:ok, pid}
              | {:ok, pid, state}
              | {:error, reason :: term}

  @doc """
  Called before stopping the application.

  This function is called before the top-level supervisor is terminated. It
  receives the state returned by `c:start/2`, if it did, or `[]` otherwise.
  The return value is later passed to `c:stop/1`.
  """
  @callback prep_stop(state) :: state

  @doc """
  Called after an application has been stopped.

  This function is called after an application has been stopped, i.e., after its
  supervision tree has been stopped. It should do the opposite of what the
  `c:start/2` callback did, and should perform any necessary cleanup. The return
  value of this callback is ignored.

  `state` is the state returned by `c:start/2`, if it did, or `[]` otherwise.
  If the optional callback `c:prep_stop/1` is present, `state` is its return
  value instead.

  `use Application` defines a default implementation of this function which does
  nothing and just returns `:ok`.
  """
  @callback stop(state) :: term

  @doc """
  Start an application in synchronous phases.

  This function is called after `start/2` finishes but before
  `Application.start/2` returns. It will be called once for every start phase
  defined in the application's (and any included applications') specification,
  in the order they are listed in.
  """
  @callback start_phase(phase :: term, start_type, phase_args :: term) ::
              :ok | {:error, reason :: term}

  @optional_callbacks start_phase: 3, prep_stop: 1

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Application

      @doc false
      def stop(_state) do
        :ok
      end

      defoverridable Application
    end
  end

  @type app :: atom
  @type key :: atom
  @type value :: term
  @type state :: term
  @type start_type :: :normal | {:takeover, node} | {:failover, node}
  @type restart_type :: :permanent | :transient | :temporary

  @application_keys [
    :description,
    :id,
    :vsn,
    :modules,
    :maxP,
    :maxT,
    :registered,
    :included_applications,
    :applications,
    :mod,
    :start_phases
  ]

  @doc """
  Returns the spec for `app`.

  The following keys are returned:

    * #{Enum.map_join(@application_keys, "\n  * ", &"`#{inspect(&1)}`")}

  Note the environment is not returned as it can be accessed via
  `fetch_env/2`. Returns `nil` if the application is not loaded.
  """
  @spec spec(app) :: [{key, value}] | nil
  def spec(app) do
    case :application.get_all_key(app) do
      {:ok, info} -> :lists.keydelete(:env, 1, info)
      :undefined -> nil
    end
  end

  @doc """
  Returns the value for `key` in `app`'s specification.

  See `spec/1` for the supported keys. If the given
  specification parameter does not exist, this function
  will raise. Returns `nil` if the application is not loaded.
  """
  @spec spec(app, key) :: value | nil
  def spec(app, key) when key in @application_keys do
    case :application.get_key(app, key) do
      {:ok, value} -> value
      :undefined -> nil
    end
  end

  @doc """
  Gets the application for the given module.

  The application is located by analyzing the spec
  of all loaded applications. Returns `nil` if
  the module is not listed in any application spec.
  """
  @spec get_application(atom) :: atom | nil
  def get_application(module) when is_atom(module) do
    case :application.get_application(module) do
      {:ok, app} -> app
      :undefined -> nil
    end
  end

  @doc """
  Returns all key-value pairs for `app`.
  """
  @spec get_all_env(app) :: [{key, value}]
  def get_all_env(app) do
    :application.get_all_env(app)
  end

  @doc """
  Returns the value for `key` in `app`'s environment.

  If the configuration parameter does not exist, the function returns the
  `default` value.

  ## Examples

  `get_env/3` is commonly used to read the configuration of your OTP applications.
  Since Mix configurations are commonly used to configure applications, we will use
  this as a point of illustration.

  Consider a new application `:my_app`. `:my_app` contains a database engine which
  supports a pool of databases. The database engine needs to know the configuration for
  each of those databases, and that configuration is supplied by key-value pairs in
  environment of `:my_app`.

      config :my_app, Databases.RepoOne,
        # A database configuration
        ip: "localhost",
        port: 5433

      config :my_app, Databases.RepoTwo,
        # Another database configuration (for the same OTP app)
        ip: "localhost",
        port: 20717

      config :my_app, my_app_databases: [Databases.RepoOne, Databases.RepoTwo]

  Our database engine used by `:my_app` needs to know what databases exist, and
  what the database configurations are. The database engine can make a call to
  `get_env(:my_app, :my_app_databases)` to retrieve the list of databases (specified
  by module names). Our database engine can then traverse each repository in the
  list and then call `get_env(:my_app, Databases.RepoOne)` and so forth to retrieve
  the configuration of each one.

  **Important:** if you are writing a library to be used by other developers,
  it is generally recommended to avoid the application environment, as the
  application environment is effectively a global storage. For more information,
  read our [library guidelines](/library-guidelines.html).
  """
  @spec get_env(app, key, value) :: value
  def get_env(app, key, default \\ nil) do
    :application.get_env(app, key, default)
  end

  @doc """
  Returns the value for `key` in `app`'s environment in a tuple.

  If the configuration parameter does not exist, the function returns `:error`.
  """
  @spec fetch_env(app, key) :: {:ok, value} | :error
  def fetch_env(app, key) do
    case :application.get_env(app, key) do
      {:ok, value} -> {:ok, value}
      :undefined -> :error
    end
  end

  @doc """
  Returns the value for `key` in `app`'s environment.

  If the configuration parameter does not exist, raises `ArgumentError`.
  """
  @spec fetch_env!(app, key) :: value
  def fetch_env!(app, key) do
    case fetch_env(app, key) do
      {:ok, value} ->
        value

      :error ->
        vsn = :application.get_key(app, :vsn)
        app = inspect(app)
        key = inspect(key)

        case vsn do
          {:ok, _} ->
            raise ArgumentError,
                  "could not fetch application environment #{key} for application #{app} " <>
                    "because configuration #{key} was not set"

          :undefined ->
            raise ArgumentError,
                  "could not fetch application environment #{key} for application #{app} " <>
                    "because the application was not loaded/started. If your application " <>
                    "depends on #{app} at runtime, make sure to load/start it or list it " <>
                    "under :extra_applications in your mix.exs file"
        end
    end
  end

  @doc """
  Puts the `value` in `key` for the given `app`.

  ## Options

    * `:timeout` - the timeout for the change (defaults to `5_000` milliseconds)
    * `:persistent` - persists the given value on application load and reloads

  If `put_env/4` is called before the application is loaded, the application
  environment values specified in the `.app` file will override the ones
  previously set.

  The persistent option can be set to `true` when there is a need to guarantee
  parameters set with this function will not be overridden by the ones defined
  in the application resource file on load. This means persistent values will
  stick after the application is loaded and also on application reload.
  """
  @spec put_env(app, key, value, timeout: timeout, persistent: boolean) :: :ok
  def put_env(app, key, value, opts \\ []) do
    :application.set_env(app, key, value, opts)
  end

  @doc """
  Deletes the `key` from the given `app` environment.

  See `put_env/4` for a description of the options.
  """
  @spec delete_env(app, key, timeout: timeout, persistent: boolean) :: :ok
  def delete_env(app, key, opts \\ []) do
    :application.unset_env(app, key, opts)
  end

  @doc """
  Ensures the given `app` is started.

  Same as `start/2` but returns `:ok` if the application was already
  started. This is useful in scripts and in test setup, where test
  applications need to be explicitly started:

      :ok = Application.ensure_started(:my_test_dep)

  """
  @spec ensure_started(app, restart_type) :: :ok | {:error, term}
  def ensure_started(app, type \\ :temporary) when is_atom(app) do
    :application.ensure_started(app, type)
  end

  @doc """
  Ensures the given `app` and its applications are started.

  Same as `start/2` but also starts the applications listed under
  `:applications` in the `.app` file in case they were not previously
  started.
  """
  @spec ensure_all_started(app, restart_type) :: {:ok, [app]} | {:error, {app, term}}
  def ensure_all_started(app, type \\ :temporary) when is_atom(app) do
    :application.ensure_all_started(app, type)
  end

  @doc """
  Starts the given `app`.

  If the `app` is not loaded, the application will first be loaded using `load/1`.
  Any included application, defined in the `:included_applications` key of the
  `.app` file will also be loaded, but they won't be started.

  Furthermore, all applications listed in the `:applications` key must be explicitly
  started before this application is. If not, `{:error, {:not_started, app}}` is
  returned, where `app` is the name of the missing application.

  In case you want to automatically load **and start** all of `app`'s dependencies,
  see `ensure_all_started/2`.

  The `type` argument specifies the type of the application:

    * `:permanent` - if `app` terminates, all other applications and the entire
      node are also terminated.

    * `:transient` - if `app` terminates with `:normal` reason, it is reported
      but no other applications are terminated. If a transient application
      terminates abnormally, all other applications and the entire node are
      also terminated.

    * `:temporary` - if `app` terminates, it is reported but no other
      applications are terminated (the default).

  Note that it is always possible to stop an application explicitly by calling
  `stop/1`. Regardless of the type of the application, no other applications will
  be affected.

  Note also that the `:transient` type is of little practical use, since when a
  supervision tree terminates, the reason is set to `:shutdown`, not `:normal`.
  """
  @spec start(app, restart_type) :: :ok | {:error, term}
  def start(app, type \\ :temporary) when is_atom(app) do
    :application.start(app, type)
  end

  @doc """
  Stops the given `app`.

  When stopped, the application is still loaded.
  """
  @spec stop(app) :: :ok | {:error, term}
  def stop(app) do
    :application.stop(app)
  end

  @doc """
  Loads the given `app`.

  In order to be loaded, an `.app` file must be in the load paths.
  All `:included_applications` will also be loaded.

  Loading the application does not start it nor load its modules, but
  it does load its environment.
  """
  @spec load(app) :: :ok | {:error, term}
  def load(app) when is_atom(app) do
    :application.load(app)
  end

  @doc """
  Unloads the given `app`.

  It will also unload all `:included_applications`.
  Note that the function does not purge the application modules.
  """
  @spec unload(app) :: :ok | {:error, term}
  def unload(app) when is_atom(app) do
    :application.unload(app)
  end

  @doc """
  Gets the directory for app.

  This information is returned based on the code path. Here is an
  example:

      File.mkdir_p!("foo/ebin")
      Code.prepend_path("foo/ebin")
      Application.app_dir(:foo)
      #=> "foo"

  Even though the directory is empty and there is no `.app` file
  it is considered the application directory based on the name
  "foo/ebin". The name may contain a dash `-` which is considered
  to be the app version and it is removed for the lookup purposes:

      File.mkdir_p!("bar-123/ebin")
      Code.prepend_path("bar-123/ebin")
      Application.app_dir(:bar)
      #=> "bar-123"

  For more information on code paths, check the `Code` module in
  Elixir and also Erlang's [`:code` module](http://www.erlang.org/doc/man/code.html).
  """
  @spec app_dir(app) :: String.t()
  def app_dir(app) when is_atom(app) do
    case :code.lib_dir(app) do
      lib when is_list(lib) -> IO.chardata_to_string(lib)
      {:error, :bad_name} -> raise ArgumentError, "unknown application: #{inspect(app)}"
    end
  end

  @doc """
  Returns the given path inside `app_dir/1`.

  If `path` is a string, then it will be used as the path inside `app_dir/1`. If
  `path` is a list of strings, it will be joined (see `Path.join/1`) and the result
  will be used as the path inside `app_dir/1`.

  ## Examples

      File.mkdir_p!("foo/ebin")
      Code.prepend_path("foo/ebin")

      Application.app_dir(:foo, "my_path")
      #=> "foo/my_path"

      Application.app_dir(:foo, ["my", "nested", "path"])
      #=> "foo/my/nested/path"

  """
  @spec app_dir(app, String.t() | [String.t()]) :: String.t()
  def app_dir(app, path)

  def app_dir(app, path) when is_binary(path) do
    Path.join(app_dir(app), path)
  end

  def app_dir(app, path) when is_list(path) do
    Path.join([app_dir(app) | path])
  end

  @doc """
  Returns a list with information about the applications which are currently running.
  """
  @spec started_applications(timeout) :: [{app, description :: charlist(), vsn :: charlist()}]
  def started_applications(timeout \\ 5000) do
    :application.which_applications(timeout)
  end

  @doc """
  Returns a list with information about the applications which have been loaded.
  """
  @spec loaded_applications :: [{app, description :: charlist(), vsn :: charlist()}]
  def loaded_applications do
    :application.loaded_applications()
  end

  @doc """
  Formats the error reason returned by `start/2`,
  `ensure_started/2`, `stop/1`, `load/1` and `unload/1`,
  returns a string.
  """
  @spec format_error(any) :: String.t()
  def format_error(reason) do
    try do
      do_format_error(reason)
    catch
      # A user could create an error that looks like a built-in one
      # causing an error.
      :error, _ ->
        inspect(reason)
    end
  end

  # exit(:normal) call is special cased, undo the special case.
  defp do_format_error({{:EXIT, :normal}, {mod, :start, args}}) do
    Exception.format_exit({:normal, {mod, :start, args}})
  end

  # {:error, reason} return value
  defp do_format_error({reason, {mod, :start, args}}) do
    Exception.format_mfa(mod, :start, args) <>
      " returned an error: " <> Exception.format_exit(reason)
  end

  # error or exit(reason) call, use exit reason as reason.
  defp do_format_error({:bad_return, {{mod, :start, args}, {:EXIT, reason}}}) do
    Exception.format_exit({reason, {mod, :start, args}})
  end

  # bad return value
  defp do_format_error({:bad_return, {{mod, :start, args}, return}}) do
    Exception.format_mfa(mod, :start, args) <> " returned a bad value: " <> inspect(return)
  end

  defp do_format_error({:already_started, app}) when is_atom(app) do
    "already started application #{app}"
  end

  defp do_format_error({:not_started, app}) when is_atom(app) do
    "not started application #{app}"
  end

  defp do_format_error({:bad_application, app}) do
    "bad application: #{inspect(app)}"
  end

  defp do_format_error({:already_loaded, app}) when is_atom(app) do
    "already loaded application #{app}"
  end

  defp do_format_error({:not_loaded, app}) when is_atom(app) do
    "not loaded application #{app}"
  end

  defp do_format_error({:invalid_restart_type, restart}) do
    "invalid application restart type: #{inspect(restart)}"
  end

  defp do_format_error({:invalid_name, name}) do
    "invalid application name: #{inspect(name)}"
  end

  defp do_format_error({:invalid_options, opts}) do
    "invalid application options: #{inspect(opts)}"
  end

  defp do_format_error({:badstartspec, spec}) do
    "bad application start specs: #{inspect(spec)}"
  end

  defp do_format_error({'no such file or directory', file}) do
    "could not find application file: #{file}"
  end

  defp do_format_error(reason) do
    Exception.format_exit(reason)
  end
end
