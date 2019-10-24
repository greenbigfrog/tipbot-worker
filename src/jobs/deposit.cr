class TB::Worker::DepositJob < Mosquito::PeriodicJob
  run_every 1.minute

  def perform
    coins = TB::Data::Coin.read_all

    TB::DATA.transaction do |db_tx|
      db = db_tx.connection

      begin
        new_deposits = TB::Data::Deposit.read_new(db)
        log("There are #{new_deposits.size} pending deposits")

        new_deposits.each do |deposit|
          log "---"
          log("Processing deposit: #{deposit}")
          coin = coins[deposit.coin]
          api = TB::CoinApi.new(coin, Logger.new(STDOUT), backoff: false)

          tx = api.get_transaction(deposit.txhash)
          next deposit.mark_never(db) unless tx.is_a?(Hash(String, JSON::Any))

          confirmations = tx["confirmations"].as_i
          if confirmations < coin.confirmations
            log("Transaction doesn't have enough confirmations yet. Only #{confirmations} out of #{coin.confirmations}")
            next
          else
            log("Transaction has #{confirmations} confirmations")
          end

          details_array = tx["details"].as_a
          next deposit.mark_never(db) unless details_array.is_a?(Array(JSON::Any))

          details_array.each do |details|
            details = details.as_h
            next deposit.mark_never(db) unless details.is_a?(Hash(String, JSON::Any))

            if details["category"] != "receive"
              log("Category of transaction is not receive")
              next deposit.mark_never(db)
            end

            address = details["address"].as_s

            amount = details["amount"].as_f
            amount = BigDecimal.new(amount)
            deposit_address = TB::Data::DepositAddress.read(address)

            if deposit_address && deposit_address.active
              log("Deposit address is #{deposit_address}")
            else
              log("Deposit address either isn't valid, or not active")
              if id = deposit_address.try &.account_id
                next deposit.mark_never_with_account(id, db)
              else
                next deposit.mark_never(db)
              end
            end

            account = TB::Data::Account.read(deposit_address.account_id)
            log("Deposit is for account: #{account}")

            account.deposit(amount, coin, deposit.txhash, db)
            log("Deposit has been credited")

            deposit_address.deactivate
            log("Deposit address has been deactivated")

            deposit.mark_credited(account.id, db)
            log("Deposit has been marked as processed")

            log("It took #{Time.now - deposit.created_time} to process the deposit")

            # TODO send_msg
          end
        end
      rescue ex : PQ::PQError
        db_tx.rollback
        raise "Something went wrong while crediting deposit: #{ex}"
      end
    end
  end

  # private def send_msg(platform : String, coin : TB::Data::Coin, msg : String)
  #   case platform
  #   when "discord" then Discord::Client.new(coin.discord_token.not_nil!).create_message(destination.to_u64, msg)
  #   when "twitch" then log "Not implemented yet" # TODO
  #   end
  # end
end
