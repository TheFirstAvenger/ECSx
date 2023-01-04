defmodule Mix.Tasks.Ecsx.Gen.Component do
  @shortdoc "Generates a new ECSx Component type"

  @moduledoc """
  Generates a new Component type for an ECSx application.

      $ mix ecsx.gen.component Height integer

  The first argument is the name of the component, followed by the data type of the value.

  Valid types for the component's value are:

    * atom
    * binary
    * datetime
    * float
    * integer

  By default, new component types are generated with `unique: true`, which allows an entity to have at most one component of this type at any given time.  To override this, use the `--no-unique` flag:

      $ mix ecsx.gen.component Friendship binary --no-unique

  """

  use Mix.Task
  import Mix.Tasks.ECSx.Helpers, only: [otp_app: 0, root_module: 0]

  @valid_value_types ~w(atom binary datetime float integer)

  @doc false
  def run([]) do
    "Invalid arguments."
    |> message_with_help()
    |> Mix.raise()
  end

  def run([_component_type]) do
    "Invalid arguments - must provide value type. If you don't want to store a value, try `mix ecsx.gen.tag`"
    |> message_with_help()
    |> Mix.raise()
  end

  def run([component_type_name, value_type | opts]) do
    value_type = validate(value_type)
    {opts, _, _} = OptionParser.parse(opts, strict: [unique: :boolean])
    create_component_file(component_type_name, value_type, opts)
    inject_component_module_into_manager(component_type_name)
  end

  defp message_with_help(message) do
    """
    #{message}

    mix ecsx.gen.component expects a component module name (in PascalCase), followed by a valid value type.

    For example:

        mix ecsx.gen.component MyComponentType binary

    """
  end

  defp validate(type) when type in @valid_value_types, do: String.to_atom(type)

  defp validate(_),
    do: Mix.raise("Invalid value type. Possible types are: #{inspect(@valid_value_types)}")

  defp create_component_file(component_type_name, value_type, opts) do
    filename = Macro.underscore(component_type_name)
    target = "lib/#{otp_app()}/components/#{filename}.ex"
    source = Application.app_dir(:ecsx, "/priv/templates/component.ex")

    binding = [
      app_name: root_module(),
      unique: Keyword.get(opts, :unique, true),
      component_type: component_type_name,
      value: value_type
    ]

    Mix.Generator.create_file(target, EEx.eval_file(source, binding))
  end

  defp inject_component_module_into_manager(component_type) do
    manager_path = "lib/#{otp_app()}/manager.ex"
    {before_components, after_components, list} = parse_manager(manager_path)

    new_list =
      component_type
      |> add_component_to_list(list)
      |> ensure_list_format()

    new_contents =
      [before_components, "def components do\n    ", new_list, "\n  end", after_components]
      |> IO.iodata_to_binary()
      |> Code.format_string!()

    Mix.shell().info([:green, "* injecting ", :reset, manager_path])
    File.write!(manager_path, [new_contents, "\n"])
  end

  defp parse_manager(path) do
    file = File.read!(path)
    [top, rest] = String.split(file, "def components do", parts: 2)
    [list, bottom] = String.split(rest, "end", parts: 2)

    {top, bottom, list}
  end

  defp add_component_to_list(component_type, list_as_string) do
    {result, _binding} = Code.eval_string(list_as_string)

    component_type
    |> full_component_module()
    |> then(&[&1 | result])
    |> inspect()
  end

  defp full_component_module(component_type) do
    Module.concat([root_module(), "Components", component_type])
  end

  # Adds a newline to ensure the list is formatted with one component per line
  defp ensure_list_format(list_as_string) do
    ["[" | rest] = String.graphemes(list_as_string)

    ["[\n" | rest]
  end
end