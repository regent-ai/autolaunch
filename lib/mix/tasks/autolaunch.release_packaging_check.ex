defmodule Mix.Tasks.Autolaunch.ReleasePackagingCheck do
  @moduledoc false

  use Mix.Task

  @shortdoc "Checks release packaging covers production dependency inputs"
  @dockerfile "Dockerfile"

  @impl Mix.Task
  def run(_args) do
    dockerfile = File.read!(@dockerfile)
    repo_root = File.cwd!()
    build_context = Path.dirname(repo_root)

    missing_path_deps =
      repo_root
      |> local_production_path_deps()
      |> Enum.reject(&dockerfile_copies_path?(dockerfile, build_context, &1))

    missing_asset_install? = not String.contains?(dockerfile, "npm --prefix assets ci")

    cond do
      missing_path_deps != [] ->
        Enum.each(missing_path_deps, fn {app, path} ->
          Mix.shell().error(
            "local production dependency is not copied into the release image: #{app} #{path}"
          )
        end)

        Mix.raise("Autolaunch release packaging is missing production dependency inputs")

      missing_asset_install? ->
        Mix.raise("Autolaunch release image must run npm --prefix assets ci before assets.deploy")

      true ->
        Mix.shell().info("Autolaunch release packaging covers production dependency inputs")
    end
  end

  defp local_production_path_deps(repo_root) do
    Mix.Project.config()
    |> Keyword.fetch!(:deps)
    |> Enum.flat_map(fn
      {app, opts} when is_list(opts) ->
        path_dep(app, opts, repo_root)

      {app, _requirement, opts} when is_list(opts) ->
        path_dep(app, opts, repo_root)

      _dep ->
        []
    end)
  end

  defp path_dep(app, opts, repo_root) do
    if Keyword.has_key?(opts, :path) and production_dep?(opts) do
      [{app, opts |> Keyword.fetch!(:path) |> Path.expand(repo_root)}]
    else
      []
    end
  end

  defp production_dep?(opts) do
    case Keyword.get(opts, :only) do
      nil -> true
      env when is_atom(env) -> env == :prod
      envs when is_list(envs) -> :prod in envs
    end
  end

  defp dockerfile_copies_path?(dockerfile, build_context, {_app, path}) do
    dockerfile
    |> String.split("\n")
    |> Enum.flat_map(&copy_sources/1)
    |> Enum.map(&Path.expand(&1, build_context))
    |> Enum.any?(fn copied_path ->
      path == copied_path or String.starts_with?(path, copied_path <> "/")
    end)
  end

  defp copy_sources("COPY " <> rest) do
    rest
    |> String.split()
    |> Enum.drop_while(&String.starts_with?(&1, "--"))
    |> Enum.drop(-1)
  end

  defp copy_sources(_line), do: []
end
