class ApplicationController < ActionController::Base
  # JSON 統一回傳格式（mirrors PrjAGWms's ApplicationController#render_json）
  def render_json(actor, data: nil)
    if actor.success?
      render json: { status: 0, message: t(".success"), data: data }
    else
      logger.error "[#{controller_name}##{action_name}] #{actor.error}"
      render json: { status: -1, message: t(".fail"), error: actor.error }
    end
  end
end
