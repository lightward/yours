class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def current_resonance
    return nil unless session[:google_id]

    @current_resonance ||= begin
      google_id = session[:google_id]
      google_id_hash = Digest::SHA256.hexdigest(google_id)
      resonance = Resonance.find_by(encrypted_google_id_hash: google_id_hash)
      resonance.google_id = google_id if resonance
      resonance
    end
  end
  helper_method :current_resonance

  def require_authentication
    redirect_to root_path, alert: "Please sign in" unless current_resonance
  end

  def require_active_subscription
    return if current_resonance&.active_subscription?

    redirect_to subscribe_path, alert: "Active subscription required"
  end
end
