# Extends google_sign_in gem's callback controller to handle native app OAuth
#
# Native apps using ASWebAuthenticationSession lose Rails flash state between
# the authorization and callback requests. We detect this (missing flash[:proceed_to])
# and redirect to a custom URL scheme instead, passing a one-time bootstrap token.
require "google_sign_in/redirect_protector"

class GoogleSignIn::CallbacksController < GoogleSignIn::BaseController
  def show
    if native_app_callback?
      # For Turbo Native apps using ASWebAuthenticationSession,
      # flash won't persist across the OAuth flow. Handle auth response
      # and redirect to custom URL scheme directly.
      if valid_params? && params[:code].present?
        begin
          # Exchange code for id_token
          id_token_value = client.auth_code.get_token(params[:code])["id_token"]
          identity = GoogleSignIn::Identity.new(id_token_value)
          google_id = identity.user_id

          # Create or find resonance (for side effect)
          Resonance.find_or_create_by_google_id(google_id)

          # Generate a stateless auth token (no storage needed)
          auth_token = Resonance.generate_auth_token(google_id)

          # Redirect with token in URL
          redirect_to "lightward-yours://authenticated?token=#{CGI.escape(auth_token)}", allow_other_host: true
        rescue OAuth2::Error => error
          redirect_to "lightward-yours://auth-error?message=#{CGI.escape(error.code)}", allow_other_host: true
        end
      else
        error = params[:error] || "invalid_request"
        redirect_to "lightward-yours://auth-error?message=#{CGI.escape(error)}", allow_other_host: true
      end
    else
      # For web browsers, use the gem's default behavior
      redirect_to proceed_to_url, flash: { google_sign_in: google_sign_in_response }
      clear_redeemed_flash_keys if valid_request?
    end
  rescue GoogleSignIn::RedirectProtector::Violation => error
    logger.error error.message
    head :bad_request
  end

  private
    # Native apps lose flash state in ASWebAuthenticationSession
    def native_app_callback?
      flash[:proceed_to].nil? && params[:state].present?
    end

    def valid_params?
      params[:state].present?
    end

    def proceed_to_url
      flash[:proceed_to].tap { |url| GoogleSignIn::RedirectProtector.ensure_same_origin(url, request.url) }
    end

    def google_sign_in_response
      if valid_request? && params[:code].present?
        { id_token: id_token }
      else
        { error: error_message_for(params[:error]) }
      end
    rescue OAuth2::Error => error
      { error: error_message_for(error.code) }
    end

    def valid_request?
      flash[:state].present? && params[:state] == flash[:state]
    end

    def id_token
      client.auth_code.get_token(params[:code])["id_token"]
    end

    def error_message_for(error_code)
      error_code.presence_in(GoogleSignIn::OAUTH2_ERRORS) || "invalid_request"
    end

    def clear_redeemed_flash_keys
      flash.delete(:proceed_to)
      flash.delete(:state)
    end
end
