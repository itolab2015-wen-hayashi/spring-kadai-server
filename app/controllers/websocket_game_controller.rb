#encoding: utf-8
# Websocket を使った GameController
#
class WebsocketGameController < WebsocketRails::BaseController

	# 最大ゲームスコア. このスコアをユーザが超えたらゲーム終了.
	GAME_END_SCORE = 1000

	# 初期化
	#
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
		controller_store[:clients][:client_id] = {
			:connection => connection(),
			:score => 0
		}
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
		received_message = message()
		logger.debug("game_message: #{received_message}")

		# :websocket_game イベントをブロードキャスト
		broadcast_message(:websocket_game, received_message)
	end

	# クライアントにてタイルが押されたときのイベントハンドラ
	# 
	def tile_pushed
		logger.debug("tile_pushed!")
		client_id = client_id()
		received_message = message()
		logger.debug(" message = #{received_message}")
		logger.debug(" elapsedTime = #{received_message[:elapsed_time]}")

		if controller_store[:round][:state] == "WAITING" then
			controller_store[:round][:state] = "PUSHED"

			# とりあえず勝者を決定
			controller_store[:round][:winner] = client_id,
			controller_store[:round][:min_elapsed_time] = received_message[:elapsed_time]

			# --> 全員にブロードキャスト
			broadcast_message(:winner_approval, received_message)
		end

	end

	# クライアントから勝者決定の同意/不同意が送られた時のイベントハンドラ
	# 
	def winner_approval
		client_id = client_id()
		received_message = message()

		if controller_store[:round][:state] == "PUSHED" then
			controller_store[:clients_in_round].delete(client_id)

			# 勝者を更新
			if received_message[:elapsed_time] < controller_store[:round][:min_elapsed_time] then
				controller_store[:round][:winner] = client_id,
				controller_store[:round][:min_elapsed_time] = received_message[:elapsed_time]
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
			:min_elapsed_time => 0,
			:add_score => 100
		}

		# メッセージ送信
		message_to_send = {
			:trigger_time => 0
		}

		broadcast_message(:new_round, message_to_send)
	end

	# ラウンドを終えるメソッド
	#
	private
	def close_round
		winner = controller_store[:round][:winner]
		controller_store[:round][:state] = "CLOSED"

		# 勝者に加点
		controller_store[:clients][winner][:score] += controller_store[:round][:add_score]

		# メッセージ送信
		message_to_send = {
			:winner => winner,
			:add_score => controller_store[:round][:add_score]
		}

		broadcast_message(:close_round, message_to_send)

		# ゲーム終了の判断
		if controller_store[:clients][winner][:score] > GAME_END_SCORE then
			close_game(winner)
		end
	end

	# ゲームを終えるメソッド
	#  winner: 勝者
	private
	def close_game(winner)
		# メッセージ送信
		message_to_send = {
			:winner => winner
		}

		broadcast_message(:close_game, message_to_send)
	end
end