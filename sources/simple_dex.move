module dex::simple_dex{
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};

    //Error Codes
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    const E_ZERO_AMOUNT: u64 = 2;
    const E_POOL_NOT_INITIALIZED: u64 = 3;

    struct LiquidityPool<phantom CoinTypeA, phantom CoinTypeB> has key{
        coin_a: coin::Coin<CoinTypeA>,
        coin_b: coin::Coin<CoinTypeB>,
        lp_supply: u64,
    }

    struct SwapEvent has drop, store{
        user: address,
        amount_in: u64,
        amount_out: u64,
        coin_in_type: bool, //true for A, false for B
    }

    struct Events has key{
        swap_events: EventHandle<SwapEvent>,
    }

    //Initializing a new liquidity pool
    public entry fun initialize_pool<CoinTypeA, CoinTypeB>(
        account: &signer,
        amt_a: u64,
        amt_b: u64
    ){
        let coin_a = coin::withdraw<CoinTypeA>(account, amt_a);
        let coin_b = coin::withdraw<CoinTypeB>(account, amt_b);

        assert!(amt_a > 0 && amt_b > 0 , E_ZERO_AMOUNT);

        let pool = LiquidityPool{
            coin_a,
            coin_b,
            lp_supply: amt_a * amt_b,
        };

        move_to(account, Events{
            swap_events: account::new_event_handle<SwapEvent>(account),
        });

        move_to(account,pool);
    }

    public entry fun swap_a_to_b<CoinTypeA, CoinTypeB>(
        account: &signer,
        amount_in: u64
    ) acquires LiquidityPool, Events {
        let pool = borrow_global_mut<LiquidityPool<CoinTypeA, CoinTypeB>>(@dex);

        let reserves_a = coin::value(&pool.coin_a);
        let reserves_b = coin::value(&pool.coin_b);

        let amount_out = calculate_amount_out(amount_in, reserves_a, reserves_b);
        assert!(amount_out > 0, E_INSUFFICIENT_BALANCE);

        // Transfer coins
        let coin_in = coin::withdraw<CoinTypeA>(account, amount_in);
        coin::merge(&mut pool.coin_a, coin_in);

        let coin_out = coin::extract(&mut pool.coin_b, amount_out);
        coin::deposit(signer::address_of(account), coin_out);

        let events = borrow_global_mut<Events>(@dex);
        event::emit_event(&mut events.swap_events, SwapEvent {
            user: signer::address_of(account),
            amount_in,
            amount_out,
            coin_in_type: true,
        });
    }

    fun calculate_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64
    ): u64 {
        let amount_in_with_fee = (amount_in as u128) * 997; // 0.3% fee
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * 1000 + amount_in_with_fee;
        ((numerator / denominator) as u64)
    }
}