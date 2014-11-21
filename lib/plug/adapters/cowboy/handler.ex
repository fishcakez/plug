defmodule Plug.Adapters.Cowboy.Handler do
  @moduledoc false
  @behaviour :cowboy_middleware
  @connection Plug.Adapters.Cowboy.Conn

  def execute(req, env) do
    case Keyword.fetch!(env, :handler) do
      __MODULE__ ->
        {plug, opts} = Keyword.fetch!(env, :handler_opts)
        handle_request(req, plug, opts)
      _ ->
        {:ok, req, env}
    end
  end

  defp handle_request(req, plug, opts) do
    transport_mod = :cowboy_req.get(:transport, req)
    transport = apply(transport_mod, :name, [])
    conn = @connection.conn(req, transport)
    try do
      plug.call(conn, opts)
    else
      %Plug.Conn{adapter: {@connection, req}} ->
        {:halt, req}
      other ->
        raise "Cowboy adapter expected #{inspect plug} to return Plug.Conn but got: #{inspect other}"
    catch
      class, reason ->
        stack = System.stacktrace()
        :cowboy_req.maybe_reply(stack, req)
        report_error(class, reason, stack, plug, conn, opts)
        stop(class, reason, stack)
    end
  end

  defp report_error(:exit, :normal, _, _, _, _), do: :ok
  defp report_error(:exit, :shutdown, _, _, _, _), do: :ok
  defp report_error(:exit, {:shutdown, _}, _, _, _, _), do: :ok
  defp report_error(:error, :shutdown, _, _, _, _), do: :ok

  defp report_error(class, reason, stack, plug, conn, opts) do
    reason = Exception.normalize(class, reason, stack)
    report = [plug: plug, conn: conn, opts: opts, class: class, reason: reason,
      stacktrace: stack]
    :error_logger.error_report(__MODULE__, report)
  end

  defp stop(:exit, reason, _stack), do: exit(reason)
  defp stop(:error, reason, stack), do: exit({reason, stack})
  defp stop(:throw, reason, stack), do: exit({{:nocatch, reason}, stack})
end
