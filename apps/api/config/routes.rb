# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Google OAuth routes
  post '/auth/google_oauth2', to: 'sessions#google_oauth2'
  get '/auth/google_oauth2/callback', to: 'sessions#google_callback'
  get '/auth/failure', to: 'sessions#failure'

  # Session management routes
  delete '/auth/logout', to: 'sessions#logout'

  # Incremental OAuth scope grants (require active session)
  post '/auth/grant/spreadsheets', to: 'sessions#grant_spreadsheets'
  post '/auth/grant/sync',         to: 'sessions#grant_sync'

  # API routes (versioned)
  namespace :api do
    namespace :v1 do
      # Protected API endpoints
      get    '/profile', to: 'profile#show'
      post   '/sync',    to: 'sync#create'
      delete '/reset',   to: 'sync#reset'
      get    '/status',  to: 'status#show'
      get    '/plots',   to: 'plots#show'
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
