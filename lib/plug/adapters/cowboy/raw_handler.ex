defmodule Plug.Adapters.Cowboy.NativeHandler do
  @moduledoc false
  @behaviour :cowboy_middleware
  @connection Plug.Adapters.Cowboy.Conn

  def execute(req, env) do
    continue(env, :cowboy_handler, :execute, [req, env])
  end

  def continue(env, mod, fun, args) do
    try do
      apply(mod, fun, args)
    catch
      class, reason ->
        terminate(class, reason, env)
    else
      {:ok, _, _} = ok ->
        ok
      {:suspend, mod, fun, args} ->
        {:suspend, __MODULE__, :continue, [env, mod, fun, args]}
      {:stop, _} = stop ->
        stop
    end
  end

  defp terminate(class,
      [{:reason, reason}, {:mfa, mfa}, {:stacktrace, stack} | info], env) do
    report_error(class, reason, stack, [{:mfa, mfa} | info], env)
    stop(class, reason, stack)
  end

  defp terminate(class, reason, env) do
    stack = System.stacktrace()
    report_error(class, reason, stack, [], env)
    stop(class, reason, stack)
  end

  defp report_error(:exit, :normal, _, _, _), do: :ok
  defp report_error(:exit, :shutdown, _, _, _), do: :ok
  defp report_error(:exit, {:shutdown, _}, _, _, _), do: :ok
  defp report_error(:error, :shutdown, _, _, _), do: :ok

  defp report_error(class, reason, stack, info, env) do
    listener = Keyword.fetch!(env, :listener)
    reason = Exception.normalize(class, reason, stack)
    report = [{:listener, listener}, {:pid, self()}, {:class, class},
      {:reason, reason}, {:stacktrace, stack} | info]
    :error_logger.error_report(__MODULE__, report)
  end

  defp stop(:exit, reason, _stack), do: exit(reason)
  defp stop(:error, reason, stack), do: exit({reason, stack})
  defp stop(:throw, reason, stack), do: exit({{:nocatch, reason}, stack})

end
