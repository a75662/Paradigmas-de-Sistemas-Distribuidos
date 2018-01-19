-module (replyManager).
-export ([main/0]).


main() ->
  register(?MODULE, spawn(fun() -> replyManager(#{}, #{}) end)).

% UserOrders é um map<username, [Order]>
% UserTrades é um map<username, [Trade]>
replyManager(UserOrders, UserTrades) ->
  receive
    {reply, User, _Company, _Quantity, _MinPrice, 'SELL', Trades} = SellReply ->
      NewUserOrders = reply(User, SellReply, UserOrders),
      BuyerTrades = groupBuyers(Trades),
      NewUserTrades = sendTrades(maps:keys(BuyerTrades), BuyerTrades, UserTrades),
      replyManager(NewUserOrders, NewUserTrades);
    {reply, User, _Company, _Quantity, _MaxPrice, 'SELL', Trades} = BuyReply ->
      NewUserOrders = reply(User, BuyReply, UserOrders),
      SellerTrades = groupSellers(Trades),
      NewUserTrades = sendTrades(maps:keys(SellerTrades), SellerTrades, UserTrades),
      replyManager(NewUserOrders, NewUserTrades);
    {userLogin, User, Pid} ->
      NewUserOrders = sendUserOrders(User, Pid, UserOrders),
      NewUserTrades = sendUserTrades(User, Pid, UserTrades),
      replyManager(NewUserOrders, NewUserTrades)
  end.

% envia ordens guardadas
% retorna novo UserOrders
sendUserOrders(User, Pid, UserOrders) ->
  case maps:find(User, UserOrders) of
    {ok, Orders} ->
      sendOrders(Pid, Orders),
      maps:remove(User, UserOrders);
    error ->
      UserOrders
  end.

%envia trades guardadas
% retorna novo UserTrades
sendUserTrades(User, Pid, UserTrades) ->
  case maps:find(User, UserTrades) of
    {ok, Trades} ->
      Pid ! Trades,
      maps:remove(User, UserTrades);
    error ->
      UserTrades
  end.

% envia orders separadamente
sendOrders(_, []) ->
  ok;
sendOrders(Pid, [Order | Orders]) ->
  Pid ! Order,
  sendOrders(Pid, Orders).

% recebe pids de atores ativos referentes ao User
getPids(User) ->
  authenticator ! {pids, self(), User},
  receive
    {authenticator, Res} -> Res
  end.

% responde ao cliente que adicionou a order
% retorna novo UserOrders
reply(User, Reply, UserOrders) ->
  case getPids(User) of
    [] ->
      addMapList(User, Reply, UserOrders);
    Pids ->
      sendReply(Reply, Pids),
      UserOrders
  end.

% adiciona elemento à lista de uma key
% retorna novo Map
addMapList(Key, Element, Map) ->
  case maps:find(Key, Map) of
    {ok, Elements} ->
      maps:put(Key, [Element | Elements], Map);
    error ->
      maps:put(Key, [Element], Map)
  end.

% envia o resultado da order a todas as sessões
sendReply(_, []) ->
  ok;
sendReply(Reply, [Pid | Pids]) ->
  Pid ! Reply,
  sendReply(Reply, Pids).

% agrupa trades por buyers
groupBuyers(Trades) ->
  groupBuyers(Trades, #{}).
groupBuyers([], BuyerTrades) ->
  BuyerTrades;
groupBuyers([{_, Buyer, _, _, _} = Trade | Trades], BuyerTrades) ->
  addMapList(Buyer, Trade, BuyerTrades),
  groupBuyers(Trades, BuyerTrades).

% agrupa trades por sellers
groupSellers(Trades) ->
  groupSellers(Trades, #{}).
groupSellers([], SellerTrades) ->
  SellerTrades;
groupSellers([{Seller, _, _, _, _} = Trade | Trades], SellerTrades) ->
  addMapList(Seller, Trade, SellerTrades),
  groupSellers(Trades, SellerTrades).

% envia trades aos users
% retorna novo UserTrades
sendTrades([], _, UserTrades) ->
  UserTrades;
sendTrades([User | Users], MapTrades, UserTrades) ->
  case getPids(User) of
    [] ->
      NewUserTrades = addTrades(User, MapTrades, UserTrades),
      sendTrades(Users, MapTrades, NewUserTrades);
    Pids ->
      sendReply(MapTrades, Pids),
      sendTrades(Users, MapTrades, UserTrades)
  end.

% adiciona trades de users offline
% retorna novo UserTrades
addTrades(User, MapTrades, UserTrades) ->
  case maps:find(User, UserTrades) of
    {ok, SavedTrades} ->
      maps:put(User, lists:append(SavedTrades, maps:get(User, MapTrades)), UserTrades);
    error ->
      maps:put(User, maps:get(User, MapTrades), UserTrades)
  end.
