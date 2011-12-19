
# @todo Only need certain classes
## Local modules
#require File.expand_path('../../acpc_poker_types', __FILE__)
## Local mixins
#require File.expand_path('../../mixins/easy_exceptions', __FILE__)
## Local classes
#require File.expand_path('../../bots/proxy_bot/proxy_bot', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/board_cards', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/card', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/chip_stack', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/game_definition', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/hand', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/matchstate_string', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/player', __FILE__)
#require File.expand_path('../../bots/proxy_bot/domain_types/side_pot', __FILE__)

# Gems
require 'acpc_poker_types'
require 'acpc_poker_match_state'
require 'acpc_poker_player_proxy'

require File.expand_path('../config/database_config', __FILE__)
require File.expand_path('../../app/models/match', __FILE__)


# A proxy player for the web poker application.
class WebApplicationPlayerProxy
   include AcpcPokerTypesDefs
   
   exceptions :unable_to_create_match_slice
   
   # @param [String] match_id The ID of the match in which this player is participating.
   # @param [DealerInformation] dealer_information Information about the dealer to which this bot should connect.
   # @param [String] game_definition_file_name The name of the file containing the definition of the game, of which, this match is an instance.
   # @param [String] player_names The names of the players in this match.
   # @param [Integer] number_of_hands The number of hands in this match.
   def initialize(match_id, dealer_information, game_definition_file_name, player_names='user p2', number_of_hands=1)
      @match_id = match_id
      @match_slice_index = 0
      @player_proxy = PlayerProxy.new dealer_information, game_definition_file_name, player_names, number_of_hands
      update_match_state!
   end
   
   # Player action interface
   # @see PlayerProxy#play!
   def play!(action)      
      @player_proxy.play! action
      update_match_state!
   end
   
   private
      
   def update_match_state!
      number_of_match_states_saved = 0
      @player_proxy.match_snapshots.rest(@match_slice_index).each do |match_state|
         update_database! match_state
         number_of_match_states_saved += 1
      end
      @match_slice_index += number_of_match_states_saved
   end
   
   def update_database!(match_state)
      match = Match.find(@match_id)
      players = match_state.players.map { |player| player.to_hash }
      pot = list_of_side_pot_information match_state.pot.players_involved_and_their_amounts_contributed
      pot_distribution = list_of_side_pot_information match_state.pot.players_involved_and_their_amounts_received
      player_turn_information = {submitted_small_blind: match_state.player_who_submitted_small_blind.name,
         submitted_big_blind: match_state.player_who_submitted_big_blind.name,
         whose_turn_is_next: match_state.player_whose_turn_is_next.name,
         with_the_dealer_button: match_state.player_with_the_dealer_button.name}
      betting_sequence = match_state.match_state_string.betting_sequence_string
      
      begin
         match.slices.create!(hand_has_ended: match_state.hand_ended?,
                              match_has_ended: match_state.match_ended?,
                              state_string: match_state.match_state_string.to_s,
                              # @todo Shouldn't need to pass this around
                              users_turn_to_act: match_state.users_turn_to_act?,
                              players: players,
                              pot: pot,
                              pot_distribution: pot_distribution,
                              player_turn_information: player_turn_information,
                              betting_sequence: betting_sequence,
                              player_acting_sequence: match_state.player_acting_sequence_string
                              )
         match.save
      rescue => e
         raise UnableToCreateMatchSlice, e.message
      end
   end
   
   def list_of_side_pot_information(player_to_value_hash)
      [player_to_value_hash.inject({}) do |hash, player_and_value|
          hash[player_and_value[0].name] = player_and_value[1]
          hash
      end]
   end
end
