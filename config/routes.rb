Rails.application.routes.draw do
  root "management_pages#index"
  resource :i18n_guide, only: :show, controller: "i18n_guides"
  resources :management_pages, only: %i[index show] do
    member do
      post :reset_flags
      post :update_flags_from_pr
      post :sync_from_github
      get :get_pr_info
      get :test_scope_report
    end
  end

  resources :code_analysis, only: %i[new create], path: "code_analysis"
end
