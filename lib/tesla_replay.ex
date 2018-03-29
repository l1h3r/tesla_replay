defmodule Tesla.Middleware.Replay do
  @behaviour Tesla.Middleware

  @moduledoc """
  Simple middleware for saving/replaying response data.

  This middleware intercepts requests and either returns locally stored
  data or performs the request and saves the result to disk (to replay
  for future requests).

  ### Example usage
  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Replay, path: "priv/fixtures/"
  end
  ```

  ### Options
  - `:path` - Path to fixture files (defaults to `fixtures/`)
  - `:statuses` - List of HTTP statuses to cache or `:all` to intercept
                all requests (defaults to `200`)
  """
  require Logger

  @type env :: Tesla.Env.t()

  @type opt :: {:statuses, integer | :all} | {:path, binary}

  @type opts :: [opt]

  @compression 1

  # The default path to load/save fixtures
  @path "fixtures/"

  # The default cacheable HTTP statuses
  @statuses [200]

  @impl true
  def call(env, next, opts) do
    opts = opts || []

    env
    |> load(opts)
    |> run(next)
    |> dump(opts)
  end

  defp run({:ok, env}, _), do: env
  defp run({:error, env}, next), do: Tesla.run(env, next)

  @spec load(env :: env, opts :: keyword) :: {:ok | :error, env} | no_return
  defp load(env, opts) do
    env
    |> env_to_path(opts)
    |> File.read()
    |> case do
      {:ok, binary} ->
        {:ok, b2t(binary)}

      {:error, :enoent} ->
        {:error, env}

      {:error, reason} ->
        raise %Tesla.Error{reason: reason, message: "#{__MODULE__}: Load Failed."}
    end
  end

  @spec dump(env :: env, opts :: keyword) :: env | no_return
  defp dump(env, opts) do
    if dumpable?(env, opts) do
      env
      |> env_to_path(opts)
      |> File.write!(t2b(env))
    end

    env
  end

  @spec dumpable?(env :: env, opts :: keyword) :: boolean
  defp dumpable?(%{status: status}, opts) do
    case Keyword.get(opts, :statuses, @statuses) do
      :all -> true
      value -> status in List.wrap(value)
    end
  end

  @spec b2t(binary :: binary) :: term
  defp b2t(binary), do: :erlang.binary_to_term(binary, [:safe])

  @spec t2b(term :: term) :: binary
  defp t2b(term), do: :erlang.term_to_binary(term, compressed: @compression)

  @spec env_to_path(env :: env, opts :: keyword) :: binary
  defp env_to_path(env, opts) do
    opts
    |> expand_path()
    |> mkdir_p!()
    |> Path.join(env_to_filename(env, opts))
  end

  defp env_to_filename(env, opts) do
    env
    |> extract_url(opts)
    |> String.replace(~r/[^0-9A-Z]/i, "_")
  end

  defp extract_url(%{url: url, query: query}, opts) do
    if Keyword.get(opts, :query, true) do
      Tesla.build_url(url, query)
    else
      url
    end
  end

  @spec expand_path(opts :: keyword) :: binary
  defp expand_path(opts), do: opts |> Keyword.get(:path, @path) |> Path.expand()

  @spec mkdir_p!(path :: binary) :: binary
  defp mkdir_p!(path), do: with(:ok <- File.mkdir_p!(path), do: path)
end
