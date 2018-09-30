%%%-------------------------------------------------------------------
%%% @doc Segment data type
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(eld_segment).

%% API
-export([new/2]).
-export([match_user/2]).

%% Types
-type segment() :: #{
    key      => binary(),
    deleted  => boolean(),
    excluded => [binary()],
    included => [binary()],
    rules    => [rule()],
    salt     => binary(),
    version  => pos_integer()
}.

-type rule() :: #{
    clauses   => [eld_clause:clause()],
    weight    => undefined | non_neg_integer(),
    bucket_by => undefined | binary()
}.

-export_type([segment/0]).

%%%===================================================================
%%% API
%%%===================================================================

-spec new(binary(), map()) -> segment().
new(Key, #{
    <<"key">>      := Key,
    <<"deleted">>  := Deleted,
    <<"excluded">> := Excluded,
    <<"included">> := Included,
    <<"rules">>    := Rules,
    <<"salt">>     := Salt,
    <<"version">>  := Version
}) ->
    #{
        key      => Key,
        deleted  => Deleted,
        excluded => Excluded,
        included => Included,
        rules    => parse_rules(Rules),
        salt     => Salt,
        version  => Version
    }.

-spec match_user(segment(), eld_user:user()) -> match | no_match.
match_user(Segment, User) ->
    check_user_in_segment(Segment, User).

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec parse_rules([map()]) -> [rule()].
parse_rules(Rules) ->
    F = fun(#{<<"clauses">> := Clauses} = RuleRaw) ->
            parse_rule_optional_attributes(#{clauses => parse_clauses(Clauses)}, RuleRaw)
        end,
    lists:map(F, Rules).

-spec parse_rule_optional_attributes(map(), map()) -> rule().
parse_rule_optional_attributes(Rule, RuleRaw) ->
    Weight = maps:get(<<"weight">>, RuleRaw, undefined),
    BucketBy = maps:get(<<"bucketBy">>, RuleRaw, undefined),
    Rule#{weight := Weight, bucket_by := BucketBy}.

-spec parse_clauses([map()]) -> [eld_clause:clause()].
parse_clauses(Clauses) ->
    F = fun(Clause) -> eld_clause:new(Clause) end,
    lists:map(F, Clauses).

check_user_in_segment(Segment, User) ->
    check_user_included(Segment, User).

check_user_included(#{included := Included} = Segment, #{key := UserKey} = User) ->
    Result = lists:member(UserKey, Included),
    check_user_included_result(Result, Segment, User).

check_user_included_result(true, _Segment, _User) -> match;
check_user_included_result(false, Segment, User) ->
    check_user_excluded(Segment, User).

check_user_excluded(#{excluded := Excluded} = Segment, #{key := UserKey} = User) ->
    Result = lists:member(UserKey, Excluded),
    check_user_excluded_result(Result, Segment, User).

check_user_excluded_result(true, _Segment, _User) -> no_match;
check_user_excluded_result(false, #{rules := Rules}, User) ->
    check_rules(Rules, User).

check_rules([], _User) -> no_match;
check_rules([Rule|Rest], User) ->
    Result = check_rule(Rule, User),
    check_rule_result({Result, Rule}, Rest, User).

check_rule_result({match, _Rule}, _Rest, _User) -> match;
check_rule_result({no_match, _Rule}, Rest, User) ->
    check_rules(Rest, User).

check_rule(#{clauses := Clauses} = Rule, User) ->
    Result = check_clauses(Clauses, User),
    check_clauses_result(Result, Rule, User).

-spec check_clauses([eld_clause:clause()], eld_user:user()) -> match | no_match.
check_clauses([], _User) -> match;
check_clauses([Clause|Rest], User) ->
    % Non-segment match
    Result = eld_clause:match_user(Clause, User),
    check_clause_result(Result, Rest, User).

check_clauses_result(no_match, _Rule, _User) -> no_match;
check_clauses_result(match, Rule, User) ->
    check_rule_weight(Rule, User).

-spec check_clause_result(match | no_match, [eld_clause:clause()], eld_user:user()) -> match | no_match.
check_clause_result(no_match, _Rest, _User) -> no_match;
check_clause_result(match, Rest, User) ->
    check_clauses(Rest, User).

check_rule_weight(Rule, User) ->
    % TODO implement
    check_user_bucket(Rule, User).

check_user_bucket(_Rule, _User) ->
    % TODO implement
    no_match.
