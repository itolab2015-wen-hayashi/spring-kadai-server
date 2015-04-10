class WebsocketGameController < WebsocketRails::BaseController
  def message_receive
    received_message = message()

    # :websocket_game イベントで接続しているユーザにブロードキャスト
    broadcast_message(:websocket_game, received_message)
  end
end