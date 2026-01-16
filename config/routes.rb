Rails.application.routes.draw do
  root "management_pages#index"
  resources :management_pages, only: %i[index show] do
    member do
      post :reset_flags
      post :update_flags_from_pr
      get :get_pr_info
    end
  end

  resources :code_analysis, only: %i[new create], path: "code_analysis"
end
