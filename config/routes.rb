namespace :project_state do
  resources :summary, only: [:index]
  resources :users, only: [:show]
  resource :user, only: [:show]
  resources :state, only: [:show]
  resources :project_state_reports, only: [:index, :show, :update]
  resources :bank_holidays, only: [:index]
  get 'configure', action: :edit
  post 'configure', action: :edit
end

