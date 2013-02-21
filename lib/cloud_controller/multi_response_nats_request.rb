# Can be used to run custom callback for each NATS response
class MultiResponseNatsRequest
  class Error < StandardError; end

  def initialize(nats, subject)
    @nats = nats
    @subject = subject
    @responses = []
    @response_timeouts = []
  end

  def on_response(timeout, &response_callback)
    @responses.insert(0, response_callback)
    @response_timeouts.insert(0, timeout)
  end

  def request(data)
    raise ArgumentError, "at least one callback must be provided" if @responses.empty?
    raise ArgumentError, "request was already made" if @sid

    @sid = @nats.request(@subject, data) do |response|
      handle_received_response(response)
    end
    timeout_request
  end

  def ignore_subsequent_responses
    raise ArgumentError, "request was not yet made" unless @sid

    EM.cancel_timer(@timeout) if @timeout
    unsubscribe
  end

  private

  def handle_received_response(response)
    begin
      parsed_response = Yajl.load(response)
    rescue Yajl::ParseError => e
      error = Error.new("Failed decoding response: #{e}\n#{e.backtrace}")
    end
    timeout_request
    trigger_on_response(parsed_response, error)
  end

  def trigger_on_response(response, error)
    if response_callback = @responses.pop
      response_callback.call(response, error)
    end
  end

  def timeout_request
    EM.cancel_timer(@timeout) if @timeout

    if secs = @response_timeouts.pop
      @timeout = EM.add_timer(secs) do
        unsubscribe
        trigger_on_response(nil, Error.new("Timed out"))
      end
    end
  end

  def unsubscribe
    @nats.unsubscribe(@sid)
  end
end
