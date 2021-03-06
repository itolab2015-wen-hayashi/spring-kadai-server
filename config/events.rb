WebsocketRails::EventMap.describe do
  # You can use this file to map incoming events to controller actions.
  # One event can be mapped to any number of controller actions. The
  # actions will be executed in the order they were subscribed.
  #
  # Uncomment and edit the next line to handle the client connected event:
  #   subscribe :client_connected, :to => Controller, :with_method => :method_name
  #
  # Here is an example of mapping namespaced events:
  #   namespace :product do
  #     subscribe :new, :to => ProductController, :with_method => :new_product
  #   end
  # The above will handle an event triggered on the client like `product.new`.

  # WebsocketGameController へのマッピング
  subscribe :client_connected, to: WebsocketGameController, with_method: :client_connected
  subscribe :client_disconnected, to: WebsocketGameController, with_method: :client_disconnected
  subscribe :websocket_game, to: WebsocketGameController, with_method: :game_message
  subscribe :authenticate, to: WebsocketGameController, with_method: :authenticate
  subscribe :update_delay, to: WebsocketGameController, with_method: :update_delay
  subscribe :request_game, to: WebsocketGameController, with_method: :request_game
  subscribe :join_game, to: WebsocketGameController, with_method: :join_game
  subscribe :tile_pushed, to: WebsocketGameController, with_method: :tile_pushed
  subscribe :winner_approval, to: WebsocketGameController, with_method: :winner_approval
end
