class TB::Worker::HistoryDeposits < Mosquito::QueuedJob
  def perform
    coins = TB::Data::Coin.read_all

    coins.each do |coin_tuple|
      coin = coin_tuple[1]
      api = TB::CoinApi.new(coin, Logger.new(STDOUT), backoff: false)

      tx_list = api.list_transactions(1000).as_a

      return unless tx_list.is_a?(Array(JSON::Any))
      return unless tx_list.size > 0

      tx_list.each do |tx|
        tx = tx.as_h
        next unless tx.is_a?(Hash(String, JSON::Any))

        category = tx["category"]
        next if category.nil?
        next unless category == "receive"

        tx_hash = tx["txid"].to_s
        res = TB::Data::Deposit.create(tx_hash, coin, :new)
        if res.rows_affected > 0
          log "Found missing transaction. Inserted #{tx_hash} for processing"
        end
      end
    end
  end
end
