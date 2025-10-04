class SessionsController < ApplicationController
  def create
    Rails.logger.info "Flash contents: #{flash.inspect}"
    Rails.logger.info "Flash[:google_sign_in]: #{flash[:google_sign_in].inspect}"

    if id_token = flash[:google_sign_in]&.[]("id_token")  # String key, not symbol
      identity = GoogleSignIn::Identity.new(id_token)
      google_id = identity.user_id

      resonance = Resonance.find_or_create_by_google_id(google_id)
      session[:google_id] = google_id  # Store for encryption/decryption
      redirect_to root_path
    elsif error = flash[:google_sign_in]&.[]("error")  # String key, not symbol
      redirect_to root_path, alert: "Authentication failed: #{error}"
    else
      redirect_to root_path, alert: "Authentication failed: no token in flash"
    end
  end

  def destroy
    session[:google_id] = nil
    redirect_to root_path
  end
end
