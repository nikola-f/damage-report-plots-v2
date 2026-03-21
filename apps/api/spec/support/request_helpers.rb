module RequestHelpers
  def json_response
    @json_response ||= JSON.parse(response.body)
  end

  def auth_header(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def authenticated_get(path, token)
    get path, headers: auth_header(token)
  end

  def authenticated_post(path, token, params = {})
    post path, params: params, headers: auth_header(token)
  end

  def authenticated_delete(path, token)
    delete path, headers: auth_header(token)
  end

  # Clear cached json_response between requests
  def clear_response_cache
    @json_response = nil
  end
end
