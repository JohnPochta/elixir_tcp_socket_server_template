defmodule App do
    use Application
    def start(_type, _args) do
        import Supervisor.Spec, warn: false

        IO.puts "Starting your application ..."

    	children = [
            supervisor(WServerSup, [pool_ip, port])
        ]

        opts = [strategy: :one_for_one,
            name: App.Supervisor,
            max_seconds: 1,
            max_restarts: 999999999999]
        Supervisor.start_link(children, opts)
    end
end
defmodule WServerSup do
    use Supervisor

    def start_link(pool_ip, port), do:
        Supervisor.start_link(__MODULE__, [pool_ip, port], name: __MODULE__)

    def init([pool_ip, port]) do
        IO.puts "Starting WServerSup.."

        {:ok, ls} = :gen_tcp.listen(port, [
            {:ip,pool_ip},{:reuseaddr, true},{:active, false},{:backlog, -1},
            {:keepalive, true},{:nodelay,true},:binary])
        module = cond do
            cond1 -> SocketWorkerProcess
            cond2 -> AnotherModule
        end

        children = [
            worker(WServerAcceptor, [ls, module,
                port]),
        ]

        Supervisor.init(children, 
            strategy: :one_for_one, max_seconds: 1, max_restarts: 999999999999)
    end
end
defmodule WServerAcceptor do
    use GenServer

    def start_link(listen_socket, module, port) do
        GenServer.start_link(__MODULE__,[listen_socket, module, port],[])
    end

    def init([listen_socket, module, port]) do
        IO.puts "WServerAcceptor #{module} acceptor started on port #{port}"
        {:ok, _} = :prim_inet.async_accept(listen_socket, -1)
        {:ok, %{listen_socket: listen_socket, port: port, module: module}}
    end

    def handle_info({:inet_async, listen_socket, _, {:ok, client_socket}}, s) do
        :prim_inet.async_accept(listen_socket, -1)

        pid = :erlang.spawn(s.module, :loop, [%{port: s.port}])

        :inet_db.register_socket(client_socket, :inet_tcp)
        :ok = :gen_tcp.controlling_process(client_socket, pid)
        send(pid, {:pass_socket, client_socket})

        {:noreply,s}
    end

    def handle_info({:inet_async, _ListenSocket, _, error}, s) do
        IO.puts "async accept error #{inspect error}"
        {:stop, error, s}
    end
end
defmodule SocketWorkerProcess do

    def loop(s) do
        worker_id = gen_uid_function()
        s = Map.merge(s, %{worker_id: worker_id, logged_in: nil, user_name: nil, agent: nil, buf: <<>>})
        loop_1(s)
    end
    def loop_1(s) do
        logged_in = s[:logged_in]
        s = receive do
            {:pass_socket, socket} ->
               {:ok, {ip, _port}} = :inet.peername(socket)
                IO.puts "pool connection from #{inspect ip}"
                :ok = :inet.setopts(socket, [:binary,{:active,true},{:nodelay,true},{:keepalive,true}])
                Map.merge(s, %{socket: socket})
            {:tcp, _socket, bin} ->
                buf = s.buf <> bin
                case String.split(buf, "\n") do
                    [_] -> %{s|buf: buf}
                    frames -> 
                        [buf|t] = Enum.reverse(frames)
                        t = Enum.reverse(t)
                        s = Enum.reduce(t,s,fn(frame,s)->
                            if frame != "" do
                                json = JSX.decode!(frame)
                                IO.inspect json
                                proc_msg(json, s)
                            else s end
                        end)
                        %{s|buf: buf}
                end
            {:tcp_closed, _socket} ->
                IO.puts "miner disconnnected"
                exit({:normal, :tcp_closed})
        end
        loop_1(s)
    end

    def proc_msg(m=%{"method"=>"method.name"}, s) do
        IO.inspect m
        bin = build_reply_function(elem(rpc_id,1))
        :ok = :gen_tcp.send(s.socket, bin)
        %{s|agent: agent}
    end       
end

