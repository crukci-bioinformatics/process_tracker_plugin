namespace :project_state do
  resources :summary, only: [:index]
  resources :user, only: [:show]
  resources :state, only: [:show]
end
