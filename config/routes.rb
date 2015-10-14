namespace :project_state do
  resources :summary, only: [:index]
  resources :user, only: [:show]
  resources :state, only: [:show]
  get 'configure', action: :edit
  post 'configure', action: :edit
end
