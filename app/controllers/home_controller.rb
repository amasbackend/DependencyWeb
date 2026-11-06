class HomeController < ApplicationController
  def index
    @projects = Project.includes(:business_modules, :business_features).order(created_at: :desc)
  end
end
