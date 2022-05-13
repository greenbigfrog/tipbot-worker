
class TB::Worker::UpdateBalances < Mosquito::PeriodicJob
  run_every 1.day

  def perform
    users = TB::Data::Account.read_all

    TB::DATA.using_connection do |db|
      c = TB::Data::Coin.read
      c.each do |coin|
        log "\n\n\nCOIN: #{coin.name_short}\n\n\n"
        users.each do |user|
          log "Start: #{user.id}"
          if user.possible_balance(coin, db)
            user.update_balance(coin, db)
          end
        end
      end
    end
  end
end
