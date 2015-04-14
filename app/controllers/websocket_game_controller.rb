#encoding: utf-8
# Websocket を使った GameController
#
class WebsocketGameController < WebsocketRails::BaseController

	# 初期化
	def initialize_session
		logger.debug("initializing WebsocketGameController")
		controller_store[:event_count] = 0
		controller_store[:clients] = {}
	end

	# クライアント接続時のイベントハンドラ
	#
	def client_connected
		client_id = client_id()
		logger.debug("client connected: #{client_id}")
		controller_store[:clients][:client_id] = connection()
	end

	# クライアント切断時のイベントハンドラ
	#
	def client_disconnected
		client_id = client_id()
		logger.debug("client disconnected: #{client_id}")
		controller_store[:clients].delete(:client_id)
	end

	# テスト用メソッド
	# 
	def game_message
		message = message()

		# :websocket_game イベントをブロードキャスト
		broadcast_message(:websocket_game, message)
	end

	# クライアントにてタイルが押されたときのイベントハンドラ
	# 
	def tile_pushed
		client_id = client_id()
		message = messsage()

		if controller_store[:round][:state] == "WAITING" then
			controller_store[:round][:state] = "PUSHED"

			# とりあえず勝者を決定
			controller_store[:round][:winner] = client_id,
			controller_store[:round][:response_time] = message[:response_time]

			# --> 全員にブロードキャスト
			broadcast_message(:winner_approval, message)
		end
	end

	# クライアントから勝者決定の同意/不同意が送られた時のイベントハンドラ
	# 
	def winner_approval
		client_id = client_id()
		message = message()

		if controller_store[:round][:state] == "PUSHED" then
			controller_store[:clients_in_round].delete(client_id)

			# 勝者を更新
			if message[:response_time] < controller_store[:round][:response_time] then
				controller_store[:round][:winner] = client_id,
				controller_store[:round][:response_time] = message[:response_time]
			end

			# すべてのクライアントから結果を受信したかどうか
			if controller_store[:clients_in_round].empty? then
				close_round
			end
		end
	end

	# 新規ラウンドを開始するメソッド
	# 
	private
	def new_round
		controller_store[:clients_in_round] = controller_store[:clients].keys()
		controller_store[:round] = {
			:state => "WAITING",
			:winner => nil,
			:response_time => 0
		}

		# メッセージ送信
		message = {
			:trigger_time => 0
		}

		broadcast_message(:new_round, message)
	end

	# ラウンドを終えるメソッド
	#
	private
	def close_round()
		winner = controller_store[:round][:winner]
		controller_store[:round][:state] = "CLOSED"

		# メッセージ送信
		message = {
			:winner => winner
		}

		broadcast_message(:close_round, message)
	end
end