defmodule Norta.Feed.Fetcher do
  use GenServer, otp_app: :norta
  require Logger
  alias Norta.Feed.Parser

  @default_feed_rate 4_000 # every 4 seconds

  @service_endpoint "http://gpsinfo.norta.com/"
  @service_headers [{"Connection", "keep-alive"}]

  def start_link do
    initial_state = %{
      response_hash: nil,
      stale: [],
    }
    GenServer.start_link(__MODULE__, initial_state, name: :feed_fetcher)
  end

  def init(state) do
    Logger.info "Starting Fetcher"
    set_timer 10 # run immediately
    {:ok, state}
  end

  def handle_info(:fetch, state) do
    {state, retry_time} = fetch_vehicles |> handle_response(state)
    set_timer retry_time
    {:noreply, state}
  end

  def handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}, state) do
    hash = :crypto.hash(:md5, body)

    if state[:response_hash] == hash do
      Logger.info "md5 matched #{Base.encode64(hash)}"
    else
      vehicles = Parser.parse_vehicles(body)
      Logger.info "Found #{length(vehicles)} vehicles with hash #{Base.encode64(hash)}"
      GenEvent.notify(:feed_update_handler, {:update, vehicles})
    end

    state = %{state | response_hash: hash}

    {state, @default_feed_rate}
  end

  def handle_response({:error, %HTTPoison.Error{id: id, reason: reason}}, state) do
    Logger.info "Fetch failed with {#{inspect id}, #{inspect reason}} trying again in 2 seconds"
    {state, 1_000} # Try again in 1 second
  end

  defp fetch_vehicles do
    HTTPoison.get(@service_endpoint, @service_headers, [params: service_params])
  end

  defp service_params do
    %{key: Application.fetch_env!(:norta, :api_key)}
  end

  defp set_timer(time \\ @default_feed_rate) do
    Process.send_after(self(), :fetch, time)
  end
end
