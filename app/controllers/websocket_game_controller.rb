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
		controller_store[:devices] = {}
		controller_store[:game] = {
			:state => "CLOSED"
		}
		controller_store[:round] = {
			:state => "CLOSED"
		}
	end

	# クライアント接続時のイベントハンドラ
	#
	def client_connected
		client_id = client_id()
		logger.debug("client connected: #{client_id}")
		controller_store[:clients][client_id] = {
			:connection => connection(),
			:datetime_diff_samples => [],
			:delay_samples => [],
			:datetime_diff => 0,
			:delay => 0,
			:ptr => 0
		}

		# クライアントに id を送る
		send_message(:connect_accepted, {
			:id => client_id
		})

		check_delay connection()
	end

	# クライアント切断時のイベントハンドラ
	#
	def client_disconnected
		client_id = client_id()
		logger.debug("client disconnected: #{client_id}")
		controller_store[:clients].delete(client_id)
		controller_store[:devices].delete(client_id)

		if controller_store[:game][:state] == "RUNNING" then
			if controller_store[:game].key?(:clients) then
				controller_store[:game][:clients].delete(client_id)
			end
			
			if controller_store[:round].key?(:clients) then
				controller_store[:round][:clients].delete(client_id)
			end

			if controller_store[:round].key?(:clients) then
				if controller_store[:round][:clients].empty? then
					if controller_store[:round][:state] == "PUSHED" then
						close_round
					end
				end
			end

			if controller_store[:game].key?(:clients) then
				if controller_store[:game][:clients].empty? then
					close_game
				end
			end
		end

		logger.debug("C")
	end

	# テスト用メソッド
	# 
	def game_message
		received_message = message()
		logger.debug("game_message: #{received_message}")

		# :websocket_game イベントをブロードキャスト
		broadcast_message(:websocket_game, received_message)
	end

	# 認証する（名前とかデバイス情報とか送る）
	#
	def authenticate
		logger.debug("authenticate")
		client_id = client_id()
		received_message = message()
		logger.debug("  #{client_id}: #{received_message}")

		# デバイス名を取得 // TODO
		controller_store[:clients][client_id][:device] = {
			:name => received_message[:name]
		}
		controller_store[:devices][client_id] = received_message[:name]

		send_client_list
	end

	# 遅延を調べる
	def update_delay
		logger.debug("update_delay")
		client_id = client_id()
		received_message = message()

		now = Time.now

		sent_time = Time.iso8601(received_message[:recv_time]) # サーバが送った時刻
		recv_time = Time.iso8601(received_message[:sent_time]) # クライアントが受信した時刻
		logger.debug("  sent_time = #{sent_time}")
		logger.debug("  recv_time = #{recv_time}")

		# 時刻の差分を計算
		delay = (now - sent_time) / 2.0
		datetime_diff = (((sent_time + delay) - recv_time) + (now - (recv_time + delay))) / 2.0

		if controller_store[:clients].key?(client_id) then
			client = controller_store[:clients][client_id]

			client[:datetime_diff_samples][client[:ptr] % 5] = datetime_diff
			client[:delay_samples][client[:ptr] % 5] = delay

			client[:datetime_diff] = mean(client[:datetime_diff_samples])
			client[:delay] = mean(client[:delay_samples])
			client[:ptr] += 1
		end
		logger.debug("  clients = #{controller_store[:clients]}")

		if controller_store[:game][:max_delay] < delay then
			controller_store[:game][:max_delay] = delay
		end
		logger.debug("  max_delay = #{controller_store[:game][:max_delay]}")
	end

	# 新規ゲームをリクエスト
	#
	def request_game
		if controller_store[:game][:state] == "RUNNING" then
			# ゲーム中なので始められない
			send_message(:request_game_rejected, {})
		else
			# 新規ゲーム作成
			if controller_store[:game][:state] == "CLOSED" then
				new_game
			end
			send_message(:request_game_accepted, {})
		end
	end

	# 試合に参加する時に呼ばれるイベントハンドラ
	#
	def join_game
		logger.debug("join_game")
		client_id = client_id()
		received_message = message()

		if controller_store[:game][:state] == "WAITING" then
			# 試合情報更新
			controller_store[:game][:clients][client_id] = {
				:score => 0
			}

			# max_delay 更新
			if controller_store[:game][:max_delay] < controller_store[:clients][client_id][:delay] then
				controller_store[:game][:max_delay] = controller_store[:clients][client_id][:delay]
			end

			# 全員参加したら最初のラウンド開始
			if controller_store[:clients].length <= controller_store[:game][:clients].length then
				controller_store[:game][:state] = "RUNNING"
				new_round
			end
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
			if received_message.key?(:approve) && !received_message[:approve] then
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

	# 遅延確認
	#
	def check_delays
		sent_time = Time.now

		controller_store[:clients].each { |client_id, client|
			connection = client[:connection]
			check_delay connection
		}
	end

	private
	def check_delay(connection)
		connection.send_message :check_delay, {
			:sent_time => Time.now.iso8601(6)
		}
	end

	# クライアント一覧を送る
	#
	private
	def send_client_list
		# 接続しているクライアントにクライアント一覧リストを送る
		broadcast_message(:client_list, {
			:clients => controller_store[:clients].keys,
			:devices => controller_store[:devices]
		})
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

		check_delays
	end

	# 新規ラウンドを開始するメソッド
	# 
	private
	def new_round
		logger.debug("new_round")

		# ラウンド情報更新
		controller_store[:round] = {
			:state => "WAITING",
			:clients => controller_store[:game][:clients].keys(),
			:winner => nil,
			:min_elapsed_time => 0,
			:add_score => 100
		}
		logger.debug(" --> round = #{controller_store[:round]}")

		# タイルの設定
		x = rand(0..5)
		y = rand(0..9)
		color = rand(0..3)

		# ラウンドの開始時刻を決定
		trigger_time = Time.now + controller_store[:game][:max_delay] + (rand(1000..2000) / 1000)
		logger.debug(" --> trigger_time = #{trigger_time}")

		# それぞれのクライアントにメッセージ送信
		clients = controller_store[:clients]
		controller_store[:game][:clients].each { |client_id, client|
			datetime_diff = clients[client_id][:datetime_diff]

			message_to_send = {
				:x => x,
				:y => y,
				:color => color,
				:trigger_time => (trigger_time - datetime_diff).iso8601(6)
			}

			connection = clients[client_id][:connection]
			connection.send_message :new_round, message_to_send
		}

		check_delays
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
		if controller_store[:game][:clients].key?(winner) && controller_store[:game][:clients][winner][:score] >= Constants::GAME_END_SCORE then
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

	# 配列の平均を計算
	#
	private
	def mean(array)
		sum = 0
		for i in 0..array.length-1 do
			sum += array[i]
		end
		return (sum/array.length)
	end
end