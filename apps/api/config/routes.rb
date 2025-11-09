Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Google OAuth routes
  post '/auth/google_oauth2', to: 'sessions#google_oauth2'
  get '/auth/google_oauth2/callback', to: 'sessions#google_callback'
  get '/auth/failure', to: 'sessions#failure'

  # Session management routes
  post '/auth/refresh', to: 'sessions#refresh'
  delete '/auth/logout', to: 'sessions#logout'

  # API routes (versioned)
  namespace :api do
    namespace :v1 do
      # Protected API endpoints
      get '/profile', to: 'profile#show'
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
