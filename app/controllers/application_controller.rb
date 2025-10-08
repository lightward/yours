class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :verify_host!

  def default_url_options
    { host: ENV.fetch("HOST") }
  end

  private

  def verify_host!
    return if request.host == ENV.fetch("HOST")

    # redirect to the correct host, preserving the full path and query string
    redirect_to(
      "https://#{ENV.fetch("HOST")}#{request.fullpath}",
      status: :moved_permanently,
      allow_other_host: true,
    )
  end

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

  def obfuscated_user_email
    session[:obfuscated_user_email]
  end
  helper_method :obfuscated_user_email

  def obfuscate_email(email)
    return nil unless email
    local, domain = email.split("@")
    return email if local.nil? || domain.nil?

    # Show first 2 chars of local part, rest as ··
    local_preview = local[0..1] + "··"

    # Show first 2 chars of domain part, rest as ··
    domain_parts = domain.split(".")
    domain_preview = domain_parts[0][0..1] + "··"

    "#{local_preview}@#{domain_preview}"
  end

  def require_authentication
    redirect_to home_path, alert: "Please sign in" unless current_resonance
  end

  def require_active_subscription
    return if current_resonance&.active_subscription?

    redirect_to subscribe_path, alert: "Active subscription required"
  end
end
