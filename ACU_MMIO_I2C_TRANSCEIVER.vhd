library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--------------------------------------------------------------------------------------
entity acu_mmio_i2c_transceiver is
	generic (
		metastable_filter_bypass_acu:			boolean := true;
		metastable_filter_bypass_recover_fsm_n:	boolean := false;
			
		clk_in:									integer := 50000000;
		address_frame:							integer range 7 to 10 := 7;
				
		data_frame: 							integer :=8;
		
		address_init_comm:						integer range 0 to 65535 := 3;
		address_data:							integer range 0 to 65535 := 4;
		address_speed_ctrl:						integer range 0 to 65535 := 5;
		
		address_slave_address:					integer range 0 to 65535 := 6
		
	);
	
	port (
		clk:						in	std_logic;
		raw_reset_n:				in	std_logic;
		
		-- ACU memory-mapped I/O interface
		read_strobe_from_acu:		in	std_logic;
		write_strobe_from_acu:		in	std_logic;
		ready_2_acu:				out	std_logic;
		address_from_acu:			in	std_logic_vector (15 downto 0);
		data_from_acu:				in	std_logic_vector (15 downto 0);
		data_2_acu:					out	std_logic_vector (15 downto 0) := X"0000";
		
		
		-- User logic external interface
		SDA_in:						in std_logic;
		SDA_out:					out std_logic;
		SCL:						inout std_logic;
		output_enable:				out std_logic;
		
		-- FSM error interface
		invalid_state_error:		out	std_logic;
		recover_fsm_n:				in	std_logic;
		recover_fsm_n_ack:			out	std_logic
	);
end entity acu_mmio_i2c_transceiver;
---------------------------------------------------------------------------------------------------
architecture rtl of acu_mmio_i2c_transceiver is

	-- Reset synchronizer resources
	signal ff_reset_n:						std_logic;
	signal as_reset_n:						std_logic;
		
	-- Metastable filter resources	
	signal ff_write_strobe_from_acu:		std_logic;
	signal write_strobe_from_acu_filtered:	std_logic;
	signal write_strobe_from_acu_internal:	std_logic;
	signal ff_read_strobe_from_acu:			std_logic;
	signal read_strobe_from_acu_filtered:	std_logic;
	signal read_strobe_from_acu_internal:	std_logic;
	signal ff_recover_fsm_n:				std_logic;
	signal recover_fsm_n_filtered:			std_logic;
	signal recover_fsm_n_internal:			std_logic;
	
	
	type state_t is (
		idle,
		set_slave_address,
		set_output_buffer,
		init_communication,
		set_speed,
		read_input_buffer,
		read_transfer_done,
		set_symbol_rate,
		
		wait_for_deassert_strobes,
		error
	);
	signal state: state_t;
	attribute syn_preserve: boolean;
	attribute syn_preserve of state:signal is true;
	
	signal cs:								std_logic;
	signal s_data_2_acu:					std_logic_vector (15 downto 0);
	signal s_ready_2_acu:					std_logic;
	signal adapter_invalid_state_error:		std_logic;
	
	--signal i2c_address_frame:				integer range 7 to 10;
	
	signal i2c_data_in:						std_logic_vector (7 downto 0);
	signal i2c_data_out:					std_logic_vector (7 downto 0);
	signal i2c_slave_address:				std_logic_vector (address_frame-1 downto 0);
	signal i2c_read_or_write:				std_logic;
	signal i2c_init_comm:					std_logic;
	signal i2c_transfer_done:				std_logic;
	signal i2c_runtime_speed_ctrl:			std_logic;
	
	
	-- User logic internal interface signals
	signal i2c_fsm_invalid_state_error:		std_logic;

	
	
begin
	
	
	----------------------------------------------------------------------------------
	----------------------------------------------------------------------------------
	assert address_slave_address /= address_data report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	assert address_slave_address /= address_init_comm report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	assert address_slave_address /= address_speed_ctrl report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	assert address_data /= address_init_comm report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	assert address_data /= address_speed_ctrl report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	assert address_init_comm /= address_speed_ctrl report "ACU MMIO I2C TRANSCIEVER ADDRESSING ERROR!" severity failure;
	
	
	
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
	
	-- Reset circuitry: Active-LOW asynchronous assert, synchronous deassert with meta-stable filter.
	L_RESET_CIRCUITRY:	process ( clk, raw_reset_n )
	begin
		if ( raw_reset_n = '0' ) then
			ff_reset_n <= '0';
			as_reset_n <= '0';
		elsif ( rising_edge(clk) ) then
			ff_reset_n <= '1';
			as_reset_n <= ff_reset_n;
		end if;
	end process;
	
	--------------------------------------------------------
	--------------------------------------------------------
	--------------------------------------------------------
	
	L_METASTBLE_FILTER_BLOCK: process ( clk, as_reset_n )
	begin
		if ( as_reset_n = '0' ) then
			ff_write_strobe_from_acu <= '0';
			write_strobe_from_acu_filtered <= '0';
			ff_read_strobe_from_acu <= '0';
			read_strobe_from_acu_filtered <= '0';
			ff_recover_fsm_n <= '1';
			recover_fsm_n_filtered <= '1';
			
		elsif ( rising_edge(clk) ) then
			ff_write_strobe_from_acu <= write_strobe_from_acu;
			write_strobe_from_acu_filtered <= ff_write_strobe_from_acu;
			ff_read_strobe_from_acu <= read_strobe_from_acu;
			read_strobe_from_acu_filtered <= ff_read_strobe_from_acu;
			ff_recover_fsm_n <= recover_fsm_n;
			recover_fsm_n_filtered <= ff_recover_fsm_n;
			
		end if;
	end process;
	
	L_METASTABLE_FILTER_BYPASS: block
	begin
		write_strobe_from_acu_internal <= write_strobe_from_acu when metastable_filter_bypass_acu = true else write_strobe_from_acu_filtered;
		read_strobe_from_acu_internal <= read_strobe_from_acu when metastable_filter_bypass_acu = true else read_strobe_from_acu_filtered;
		recover_fsm_n_internal <= recover_fsm_n when metastable_filter_bypass_recover_fsm_n = true else recover_fsm_n_filtered;
		
	end block;
	
	L_METASTABLE_FILTER_ACKNOWLEDGE: block
	begin
		recover_fsm_n_ack <= recover_fsm_n_internal;
	end block;
	
	--------------------------------------------------------
	--------------------------------------------------------
	--------------------------------------------------------
	
	
	L_LOCAL_ADDRESS_DECODER: block
	begin
		cs <= '1' when (unsigned(address_from_acu) = address_slave_address or
						unsigned(address_from_acu) = address_data or
						unsigned(address_from_acu) = address_init_comm or
						unsigned(address_from_acu) = address_speed_ctrl 
						)
						else '0';
		ready_2_acu <= s_ready_2_acu when cs = '1' else '0';
		data_2_acu(15 downto 0) <= s_data_2_acu when cs = '1' else (others => '0');
	end block;
	
	--------------------------------------------------------
	--------------------------------------------------------
	--------------------------------------------------------
	
	L_ACU_2_I2C_ADAPTER: process ( clk, as_reset_n )
	begin
		if ( as_reset_n = '0' ) then
			state <= idle;
			s_ready_2_acu <= '0';
			s_data_2_acu <= (others => '0');
			
			i2c_data_in <= X"00";
			i2c_init_comm <= '0';
			
			
			adapter_invalid_state_error <= '0';
			
		elsif ( rising_edge(clk) ) then
			case state is
				when idle	=>	s_ready_2_acu <= '1';
								i2c_init_comm <= '0';
								i2c_runtime_speed_ctrl <= '0';
								-- Handle ACU writes
								if ( write_strobe_from_acu_internal = '1' and cs = '1' ) then
									
									s_ready_2_acu <= '0';
									
									if ( unsigned(address_from_acu) = address_slave_address ) then
										state <= set_slave_address;
									elsif ( unsigned(address_from_acu) = address_data ) then
										state <= set_output_buffer;
									elsif ( unsigned(address_from_acu) = address_init_comm ) then
										state <= init_communication;
									elsif ( unsigned(address_from_acu) = address_speed_ctrl) then
										state <= set_speed;
									else
										state <= wait_for_deassert_strobes;
									end if;
									
								end if;
								
								-- Handle ACU reads
								if ( read_strobe_from_acu_internal = '1' and cs = '1') then
									
									s_ready_2_acu <= '0';
									
									if ( unsigned(address_from_acu) = address_data ) then
										state <= read_input_buffer;
									
									elsif ( unsigned(address_from_acu) = address_init_comm ) then
										state <= init_communication;
								
									else
										state <= wait_for_deassert_strobes;
									end if;
									
								end if;
				
				----------------------------------------------------------------------------------------------
				-- WRITE STATES
				
				when set_slave_address	=>	i2c_slave_address <= data_from_acu(address_frame-1 downto 0);
											state <= wait_for_deassert_strobes;
				----------------------------------------------------------------------------------------------				
									
				when set_output_buffer	=>	i2c_data_in <= data_from_acu(7 downto 0);
											--i2c_read_or_write <= '1';
											state <= wait_for_deassert_strobes;
				----------------------------------------------------------------------------------------------
									
				when init_communication	=>	i2c_init_comm <= '1';
											i2c_read_or_write <= data_from_acu(0);
											state <= wait_for_deassert_strobes;
				----------------------------------------------------------------------------------------------
				
				when set_speed			=>	i2c_runtime_speed_ctrl <= '1';
											i2c_data_in(0) <= data_from_acu(0);
											state <= wait_for_deassert_strobes;
				----------------------------------------------------------------------------------------------
				
				
				
				-- READ STATES		
				
				when read_input_buffer	=>	s_data_2_acu(7 downto 0) <= i2c_data_out;
											s_data_2_acu(15 downto 8) <= X"00";
											
											state <= wait_for_deassert_strobes;
				----------------------------------------------------------------------------------------------
					
			
				
				when wait_for_deassert_strobes	=>	--i2c_init_comm <= '0';
													if ( read_strobe_from_acu_internal = '0' and write_strobe_from_acu_internal = '0' and i2c_transfer_done = '1' ) then
														state <= idle;
													end if;
													
				----------------------------------------------------------------------------------------------
				
				when error	=>	-- reset all
								s_ready_2_acu <= '0';
								s_data_2_acu <= (others => '0');
								i2c_data_in <= X"00";
								i2c_init_comm <= '0';
								
								
								if ( recover_fsm_n_internal = '0' ) then
									adapter_invalid_state_error <= '0';
									state <= idle;
								end if;
								
				when others	=>	adapter_invalid_state_error <= '1';
								state <= error;
			end case;
		end if;
	end process;
	
	--------------------------------------------------------
	--------------------------------------------------------
	--------------------------------------------------------
	
	L_I2C_TRANSCEIVER:	entity work.i2c_transceiver(rtl)
							generic map (
								metastable_filter_init_comm			=> true,
								metastable_filter_recover_fsm_n		=> true,
								
								address_frame						=> address_frame
							)
							
							port map (
								clk									=> clk,
								reset								=> raw_reset_n,
								data_in								=> i2c_data_in,
								data_out							=> i2c_data_out,
								slave_address						=> i2c_slave_address,
								init_comm							=> i2c_init_comm,
								transfer_done						=> i2c_transfer_done,
								SDA_in									=> SDA_in,
								SDA_out									=> SDA_out,
								SCL									=> SCL,
								output_enable 						=> output_enable,
								runtime_speed_ctrl					=> i2c_runtime_speed_ctrl,
								invalid_state_error					=> i2c_fsm_invalid_state_error,
								recover_fsm_n						=> recover_fsm_n_internal,
								recover_fsm_n_ack					=> open,
								read_or_write						=> i2c_read_or_write
								
								);
	
	--------------------------------------------------------
	--------------------------------------------------------
	--------------------------------------------------------
	
	invalid_state_error <= 	adapter_invalid_state_error or i2c_fsm_invalid_state_error;

end architecture rtl;
---------------------------------------------------------------------------------------------------
