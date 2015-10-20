namespace :project_state do
  resources :summary, only: [:index]
  resources :users, only: [:show]
  resource :user, only: [:show]
  resources :state, only: [:show]
  get 'configure', action: :edit
  post 'configure', action: :edit
end

