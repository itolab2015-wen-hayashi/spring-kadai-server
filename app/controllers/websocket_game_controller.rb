#encoding: utf-8
# Websocket を使った GameController
#
class WebsocketGameController < WebsocketRails::BaseController

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
		controller_store[:clients][client_id] = {
			:connection => connection(),
			:datetime_diff => 0,
			:delay => 0
		}

		# クライアントに id を送る
		send_message(:connect_accepted, {
			:id => client_id
		})

		# 接続しているクライアントにクライアント一覧リストを送る
		broadcast_message(:client_list, {
			:clients => controller_store[:clients].keys
		})

		new_game
	end

	# クライアント切断時のイベントハンドラ
	#
	def client_disconnected
		client_id = client_id()
		logger.debug("client disconnected: #{client_id}")
		controller_store[:clients].delete(client_id)
	end

	# テスト用メソッド
	# 
	def game_message
		received_message = message()
		logger.debug("game_message: #{received_message}")

		# :websocket_game イベントをブロードキャスト
		broadcast_message(:websocket_game, received_message)
	end

	# 遅延を調べる
	def update_delay
		logger.debug("update_delay")
		client_id = client_id()
		received_message = message()

		sent_time = Time.iso8601(received_message[:sent_time])
		logger.debug("  sent_time = #{sent_time}")

		# 時刻の差分を計算
		datetime_diff = sent_time - controller_store[:check_delay_sent_time]
		delay = (Time.now - controller_store[:check_delay_sent_time]) / 2.0

		if controller_store[:game][:max_delay] < delay then
			controller_store[:game][:max_delay] = delay
		end

		if controller_store[:clients].key?(client_id) then
			controller_store[:clients][client_id][:datetime_diff] = datetime_diff
			controller_store[:clients][client_id][:delay] = delay
		end
	end

	# 試合に参加する時に呼ばれるイベントハンドラ
	#
	def join_game
		logger.debug("join_game")
		client_id = client_id()
		received_message = message()

		# 試合情報更新
		controller_store[:game][:clients][client_id] = {
			:datetime_diff => controller_store[:clients][client_id][:datetime_diff],
			:score => 0
		}

		# max_delay 更新
		if controller_store[:game][:max_delay] < controller_store[:clients][client_id][:delay] then
			controller_store[:game][:max_delay] = controller_store[:clients][client_id][:delay]
		end

		# 全員参加したら最初のラウンド開始
		if controller_store[:clients].length <= controller_store[:game][:clients].length  then
			controller_store[:game][:state] = "RUNNING"
			new_round
		end
	end

	# クライアントにてタイルが押されたときのイベントハンドラ
	# 
	def tile_pushed
		logger.debug("tile_pushed")
		client_id = client_id()
		received_message = message()
		logger.debug(" message = #{received_message}")
		logger.debug(" elapsedTime = #{received_message[:elapsed_time]}")

		if controller_store[:round][:state] == "WAITING" then
			controller_store[:round][:state] = "PUSHED"

			# とりあえず勝者を決定
			controller_store[:round][:winner] = client_id
			controller_store[:round][:min_elapsed_time] = received_message[:elapsed_time]

			# --> 全員にブロードキャスト
			broadcast_message(:winner_approval, received_message)
		end

	end

	# クライアントから勝者決定の同意/不同意が送られた時のイベントハンドラ
	# 
	def winner_approval
		logger.debug("winner_approval")
		client_id = client_id()
		received_message = message()
		logger.debug(" message = #{received_message}")

		if controller_store[:round][:state] == "PUSHED" then
			controller_store[:round][:clients].delete(client_id)
			logger.debug(" --> clients in round = #{controller_store[:round][:clients]}")

			# 勝者を更新
			if !received_message[:approve] then
				if received_message[:elapsed_time] < controller_store[:round][:min_elapsed_time] then
					logger.debug("updating the winner")
					controller_store[:round][:winner] = client_id
					controller_store[:round][:min_elapsed_time] = received_message[:elapsed_time]
				end
			end

			# すべてのクライアントから結果を受信したかどうか
			if controller_store[:round][:clients].empty? then
				close_round
			end
		end
	end

	# 新規ゲームを開始するメソッド
	#
	private
	def new_game
		logger.debug("new_game")

		# 試合情報更新
		controller_store[:game] = {
			:state => "WAITING",
			:clients => {},
			:winner => nil,
			:max_delay => 0
		}
		logger.debug(" --> game = #{controller_store[:game]}")

		controller_store[:check_delay_sent_time] = Time.now
		broadcast_message(:check_delay, {})
	end

	# 新規ラウンドを開始するメソッド
	# 
	private
	def new_round
		logger.debug("new_round")

		# ラウンド情報更新
		controller_store[:round] = {
			:state => "WAITING",
			:clients => controller_store[:clients].keys(),
			:winner => nil,
			:min_elapsed_time => 0,
			:add_score => 100
		}
		logger.debug(" --> round = #{controller_store[:round]}")

		# ラウンドの開始時刻を決定
		trigger_time = Time.now + controller_store[:game][:max_delay] + (rand(1000..2000) / 1000)
		logger.debug(" --> trigger_time = #{trigger_time}")

		# それぞれのクライアントにメッセージ送信
		controller_store[:game][:clients].each { |client_id, client|
			message_to_send = {
				:trigger_time => (trigger_time + client[:datetime_diff]).iso8601(6)
			}
			connection = controller_store[:clients][client_id][:connection]
			connection.send_message :new_round, message_to_send
		}
	end

	# ラウンドを終えるメソッド
	#
	private
	def close_round
		logger.debug("close_round")

		# ラウンド情報更新
		controller_store[:round][:state] = "CLOSED"
		winner = controller_store[:round][:winner]

		# 勝者に加点
		if controller_store[:game][:clients].key?(winner) then
			controller_store[:game][:clients][winner][:score] += controller_store[:round][:add_score]
		end
		logger.debug(" --> round = #{controller_store[:round]}")

		# メッセージ送信
		message_to_send = {
			:winner => winner,
			:add_score => controller_store[:round][:add_score]
		}

		broadcast_message(:close_round, message_to_send)

		# ゲーム終了の判断
		if controller_store[:game][:clients].key?(winner) && controller_store[:game][:clients][winner][:score] > Constants::GAME_END_SCORE then
			close_game(winner)
		else
			new_round
		end
	end

	# ゲームを終えるメソッド
	#  winner: 勝者
	private
	def close_game(winner)
		logger.debug("close_game")

		# 試合情報更新
		controller_store[:game][:state] = "CLOSED"
		controller_store[:game][:winner] = winner
		logger.debug(" --> game = #{controller_store[:game]}")

		# メッセージ送信
		message_to_send = {
			:winner => winner
		}

		broadcast_message(:close_game, message_to_send)
	end
end