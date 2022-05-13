class TB::CoinApi
  def send_many(input : Hash(String, BigDecimal))
    hash = Hash(String, Float64).new
    input.each do |address, amount|
      hash[address] = amount.to_f64
    end
    @rpc.send_many("", hash).as_s
  end
end

class TB::Worker::ProcessWithdrawalsJob < Mosquito::PeriodicJob
  run_every 1.minute

  def perform
    TB::DATA.transaction do |db_tx|
      db = db_tx.connection

      begin
        input = Hash(Int32, Array(Tuple(Int32, String, BigDecimal, Int32))).new
        TB::Data::Withdrawal.read_pending_withdrawals(db).each do |x|
          input[x.coin] = Array(Tuple(Int32, String, BigDecimal, Int32)).new unless input[x.coin]?
          input[x.coin] << {x.id, x.address, x.amount, x.transaction}
        end

        if input.empty?
          log "No withdrawals to process. Succeeding early"
          db_tx.commit
          return
        end

        log "Following transactions/withdrawals are pending: #{input}"

        TB::Data::Coin.read.each do |coin|
          transactions = input[coin.id]?
          next unless transactions
          next if transactions.empty?

          rpc = TB::CoinApi.new(coin, Logger.new(STDOUT), backoff: false)
          final = Hash(String, BigDecimal).new

          transactions.each do |x|
            # Increase amount if duplicate address
            next final[x[1]] += x[2] if final[x[1]]?

            final[x[1]] = x[2]
          end

          log "Performing transaction for coin #{coin.name_short}: #{final}"

          tx = rpc.send_many(final)

          fee_per_transaction = BigDecimal.new(rpc.get_transaction(tx)["fee"].as_f.to_s) / transactions.size
          transactions.each do |x|
            TB::Data::Withdrawal.update_pending(x[0], false, db)
            fee = -1 * (coin.tx_fee + fee_per_transaction)
            TB::Data::Transaction.update_fee(x[3], BigDecimal.new(fee), db)
          end
        end
      rescue ex : PQ::PQError
        db_tx.rollback
        raise "Something went wrong while processing Withdrawal: #{ex}"
      end
    end
  end
end
