%%%----------------------------------------------------------------------
%%% File    : yaws_rss.erl
%%% Created : 15 Dec 2004 by Torbjorn Tornkvist <tobbe@tornkvist.org>
%%%
%%% @doc A Yaws RSS feed interface.
%%%
%%% @author  Torbj�rn T�rnkvist <tobbe@tornkvist.org>
%%% @end
%%%
%%% $Id$
%%%----------------------------------------------------------------------
-module(yaws_rss).

-behaviour(gen_server).

%% External exports
-export([start/0, start_link/0, open/0, open/1, close/0, close/2,
	 insert/4, insert/5, insert/6, retrieve/1]).

-export([t_setup/0, t_exp/0, t_xopen/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(s, {
	  expire = false,    % false | days
	  rm_exp = false,    % remove expired items
	  max=infinite,      % maximum number of elements in DB
	  days=7,            % maximum number of days in DB
	  counter=0}).       % item counter

-define(SERVER, ?MODULE).
-define(DB, ?MODULE).
-define(DB_FNAME, "yaws_rss.dets").
-define(ITEM(Tag, Counter, Item), {{Tag, Counter}, Item}).

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).

%%%
%%% @spec open(Dir::string()) -> {ok, DB::db()} | {error, string()}
%%%
%%% @type db(). An opaque handle leading to an RSS database.
%%%
%%% @doc See {@open/2}
%%%
open() ->
    open([]).

%%%
%%% @spec open(Dir::string(), Opts::list()) -> 
%%%         {ok, DB::db()} | {error, string()}
%%%
%%% @doc Open a RSS database, located at <em>Dir</em>.
%%%      Per default <em>dets</em> is used as database,
%%%      but by using the <em>db_mod</em> option it is
%%%      possible to use your own database.</br>
%%%      These are the options:
%%%      <p><dl>
%%%
%%%      <dt>{db_mod, Module}</dt>
%%%      <dd>If specified, the following functions will be
%%%      called:<ul>
%%%      <li>Module:open(Opts)</li>
%%%      <li>Module:insert(Tag,Title,Link,Desc,Creator,GregSec)</li>
%%%      <li>Module:retrieve(Tag) -&gt; {Title, Link, Desc, Creator, GregSecs}</li>
%%%      <li>Module:close(DbName)</li></ul>
%%%      This means that the default DB won't be used, and
%%%      no expiration handling will be done. Only the producing of
%%%      XML will thus be done. Also, the whole <em>Opts</em> will be
%%%      passed un-interpreted to the other DB module.</dd>
%%%
%%%      <dt>{db_file, File}</dt>
%%%      <dd>Specifies the full path pointing to the dets-file to be opened.</dd>
%%%      
%%%      <dt>{expire, Expire}</dt>
%%%      <dd>Specifies what method to use to expire items. Possible values
%%%      are: <em>false</em>, <em>days</em>, meaning
%%%      never expire, expire after a number of days. 
%%%      Default is to never expire items.</dd>
%%%      
%%%      <dt>{days, Number}</dt>
%%%      <dd>Specifies the number of days befor an item is expired.
%%%      Default is 7 days.</dd>
%%%
%%%      <dt>{rm_exp, Bool}</dt>
%%%      <dd>Specifies if expired items should be removed from
%%%      the database. Default is to not remove any items.</dd>
%%%
%%%      <dt>{max, Number}</dt>
%%%      <dd>Specifies the maximum number of items that should
%%%      be stored in the database. The default in <em>infinite</em></dd>
%%%      </dl></p>
%%%      <p>If no database exist, a new will be created.
%%%      The returned database handle is to be used with {@link close/1}.
%%% @end
%%%
open(Opts) ->
    gen_server:call(?SERVER, {open, Opts}, infinity).

%%%
%%% @spec close() -> ok | {error, string()}
%%%
%%% @doc Close the RSS database.
%%%
close() ->
    gen_server:call(?SERVER, {close, ?DB}, infinity).

%%%
%%% @spec close(DbMod::atom(), DbName::atom()) -> 
%%%          ok | {error, string()}
%%%
%%% @doc Close the user provided RSS database.
%%%      A call to; <em>DbMod:close(DbName)</em> will be made.
%%%
close(DBmod, DBname) ->
    gen_server:call(?SERVER, {close, DBmod, DBname}, infinity).

%%%
%%% @spec insert(Tag::atom(), Title::string(), 
%%%              Link::string(), Desc::string()) ->
%%%          ok | {error, string()}
%%%
%%% @doc Insert an RSS item into the <em>Tag</em> RSS feed.
%%%      <em>Link</em> should be a URL pointing to the item.
%%%      <p>In case another database backend is used, the 
%%%      <em>Tag</em> has the format: <em>{DbModule, OpaqueTag}</em>
%%%      where <em>DbModule</em> is the database backend module
%%%      to be called, and <em>OpaqueTag</em> the Tag that is
%%%      used in <em>DbModule:insert(Tag, ...)</em></p>
%%% @end
%%%
insert(Tag, Title, Link, Desc) ->
    insert(Tag, Title, Link, Desc, "").

%%%
%%% @spec insert(Tag::atom(), Title::string(), 
%%%              Link::string(), Desc::string(),
%%%              Creator::string()) ->
%%%          ok | {error, string()}
%%%
%%% @doc Insert an RSS item into the <em>Tag</em> RSS feed.
%%%      <em>Link</em> should be a URL pointing to the item.
%%%
insert(Tag, Title, Link, Desc, Creator) ->
    GregSecs = calendar:datetime_to_gregorian_seconds({date(),time()}),
    insert(Tag, Title, Link, Desc, Creator, GregSecs).

%%%
%%% @spec insert(Tag::atom(), Title::string(), 
%%%              Link::string(), Desc::string(),
%%%              Creator::string(), GregSecs::integer()) ->
%%%          ok | {error, string()}
%%%
%%% @doc Insert an RSS item into the <em>Tag</em> RSS feed.
%%%      <em>Link</em> should be a URL pointing to the item.
%%%      <em>GregSecs</em> is the creation time of the item
%%%      in Gregorian Seconds.
%%%
insert(Tag, Title, Link, Desc, Creator, GregSecs) ->
    Args = {Tag, Title, Link, Desc, Creator, GregSecs},
    gen_server:call(?SERVER, {insert, Args}, infinity).


%%%
%%% @spec retrieve(Tag::atom()) ->
%%%          {ok, RSScontent::IoList()} | {error, string()}
%%%
%%% @type IoList.  A deep list of strings and/or binaries.
%%%
%%% @doc Retrieve the <em>RSScontent</em> (in XML and all...)
%%%      to be delivered to a RSS client. 
%%%      <p>In case another database backend is used, the 
%%%      <em>Tag</em> has the format: <em>{DbModule, OpaqueTag}</em>
%%%      where <em>DbModule</em> is the database backend module
%%%      to be called, and <em>OpaqueTag</em> the Tag that is
%%%      used in <em>DbModule:retrieve(Tag)</em> which must return
%%%      a list of tuples: <em>{Title, Link, Desc, Creator, GregSecs}</em></p>
%%%
retrieve(Tag) ->
    gen_server:call(?SERVER, {retrieve, Tag}, infinity).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%----------------------------------------------------------------------
init([]) ->
    {ok, #s{}}.

%%----------------------------------------------------------------------
%% Func: handle_call/3
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_call({open, Opts}, _From, State) ->
    {NewState, Res} = do_open_dir(State, Opts),
    {reply, Res, NewState};
%%
handle_call({close, DB}, _From, State) ->
    dets:close(DB),
    {reply, ok, State};
%%
handle_call({close, DBMod, DBname}, _From, State) ->
    catch apply(DBMod, close, [DBname]),
    {reply, ok, State};
%%
handle_call({insert, Args}, _From, State) ->
    {NewState, Res} = do_insert(State, Args),
    {reply, Res, NewState};
%%
handle_call({retrieve, Tag}, _From, State) ->
    {NewState, Res} = do_retrieve(State, Tag),
    {reply, Res, NewState}.

%%----------------------------------------------------------------------
%% Func: handle_cast/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any (ignored by gen_server)
%%----------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

%%% 
%%% Check what database store that should be used.
%%% Per default 'dets' is used.
%%%
do_open_dir(State, Opts) -> 
    case get_db_mod(Opts, dets) of
	dets -> 
	    DefFile = yaws_config:yaws_dir() ++ "/" ++ a2l(?DB) ++ ".dets",
	    File = get_db_file(Opts, DefFile),
	    Expire = get_expire(Opts, #s.expire), 
	    Max = get_max(Opts, #s.max), 
	    Days = get_days(Opts, #s.days), 
	    RmExp = get_rm_exp(Opts, #s.rm_exp), 
	    case dets:is_dets_file(File) of
		false -> 
		    {State, {error, "not a proper dets file"}};
		_     ->
		    case catch dets:open_file(?DB, [{file, File}]) of
			{ok,_DB} = Res   -> 
			    {State#s{expire = Expire, 
				     days = Days,
				     rm_exp = RmExp,
				     max = Max}, 
			     Res};
			{error, _Reason} -> 
			    {State, {error, "open dets file"}}
		    end
	    end;
	DBmod ->
	    {State, catch apply(DBmod, open, Opts)}
    end.


do_insert(State, {{DbMod,Tag}, Title, Link, Desc, Creator, GregSecs}) ->
    {State, catch apply(DbMod, insert, [Tag,Title,Link,Desc,Creator,GregSecs])};
do_insert(State, {Tag, Title, Link, Desc, Creator, GregSecs}) ->
    Counter = if (State#s.max > 0) -> 
		      (State#s.counter + 1) rem State#s.max;
		 true -> 
		      State#s.counter + 1
	      end,
    Item = {Title, Link, Desc, Creator, GregSecs},
    Res = dets:insert(?DB, ?ITEM(Tag, Counter, Item)),
    {State#s{counter = Counter}, Res}.


do_retrieve(State, {DbMod,Tag}) ->
    {State, catch apply(DbMod, retrieve, [Tag])};
do_retrieve(State, Tag) ->
    F = fun(?ITEM(X, _Counter, Item), Acc) when X == Tag -> [Item|Acc];
	   (_, Acc)                                      -> Acc
	end,
    Items = sort_items(expired(State, dets:foldl(F, [], ?DB))),
    io:format("GOT ITEMS: ~p~n", [Items]),
    Xml = to_xml(Items),
    {State, {ok, Xml}}.


-define(ONE_DAY, 86400).  % 24*60*60 seconds
-define(X(GregSecs), {Title, Link, Desc, Creator, GregSecs}).

%%% Filter away expired items !!
expired(State, List) when State#s.expire == days ->
    Gs = calendar:datetime_to_gregorian_seconds({date(),time()}),
    Old = Gs - (?ONE_DAY * State#s.days),
    F = fun(?X(GregSecs), Acc) when GregSecs > Old ->
		[?X(GregSecs) | Acc];
	   (_, Acc) ->
		Acc
	end,
    lists:foldl(F, [], List);
expired(_State, List) ->
    List.

-undef(X).



%%%
%%% Sort on creation date !!
%%% Item = {Title, Link, Desc, Creator, GregSecs},
%%%
sort_items(Is) ->
    lists:keysort(5,Is).


to_xml([{Title, Link, Desc, Creator, GregSecs}|Tail]) ->
    {{Y,M,D},_} = calendar:gregorian_seconds_to_datetime(GregSecs),
    Date = i2l(Y) ++ "-" ++ i2l(M) ++ "-" ++ i2l(D),
    [["<item>\n",
      "<title>", Title, "</title>\n",
      "<link>", Link, "</link>\n",
      "<description>", Desc, "</description>\n",
      "<dc:creator>", Creator, "</dc:creator>\n",
      "<dc:date>", Date, "</dc:date>\n",
      "</item>\n"] | 
     to_xml(Tail)];
to_xml([]) -> 
    [].


get_db_mod(Opts, Def)  -> lkup(db_mod, Opts, Def).
get_db_file(Opts, Def) -> lkup(db_file, Opts, Def).
get_expire(Opts, Def)  -> lkup(expire, Opts, Def).
get_max(Opts, Def)     -> lkup(max, Opts, Def).
get_days(Opts, Def)    -> lkup(days, Opts, Def). 
get_rm_exp(Opts, Def ) -> lkup(rm_exp, Opts, Def).

lkup(Key, List, Def) ->
    case lists:keysearch(Key, 1, List) of
	{value,{_,Value}} -> Value;
	_                 -> Def
    end.



i2l(I) when integer(I) -> integer_to_list(I);
i2l(L) when list(L)    -> L.

a2l(A) when atom(A) -> atom_to_list(A);
a2l(L) when list(L) -> L.

     
    
 
t_setup() ->
    open([{db_file, "yaws_rss.dets"}, {max,7}]),
    insert(xml,"Normalizing XML, Part 2",
	   "http://www.xml.com/pub/a/2002/12/04/normalizing.html",
	   "In this second and final look at applying relational "
	   "normalization techniques to W3C XML Schema data modeling, "
	   "Will Provost discusses when not to normalize, the scope "
	   "of uniqueness and the fourth and fifth normal forms."),
    insert(xml,"The .NET Schema Object Model",
	   "http://www.xml.com/pub/a/2002/12/04/som.html",
	   "Priya Lakshminarayanan describes in detail the use of "
	   "the .NET Schema Object Model for programmatic manipulation "
	   "of W3C XML Schemas."),
    insert(xml,"SVG's Past and Promising Future",
	   "http://www.xml.com/pub/a/2002/12/04/svg.html",
	   "In this month's SVG column, Antoine Quint looks back at "
	   "SVG's journey through 2002 and looks forward to 2003.").


t_exp() ->
    %%open([{db_file, "yaws_rss.dets"}, {expire,days}]),
    insert(xml,"Expired article",
	   "http://www.xml.com/pub/a/2002/12/04/normalizing.html",
	   "In this second and final look at applying relational "
	   "normalization techniques to W3C XML Schema data modeling, "
	   "Will Provost discusses when not to normalize, the scope "
	   "of uniqueness and the fourth and fifth normal forms.",
	  "tobbe",
	  63269561882).  % 6/12-2004

t_xopen() ->
    open([{db_file, "yaws_rss.dets"}, 
	  {expire,days},
	  {days, 20}]).