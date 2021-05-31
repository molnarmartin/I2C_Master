----------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
---------------------------------------------------------------------------------------------------
entity i2c_transceiver is
	generic(
		
		
		clk_in: 							integer := 50000000;
		address_frame: 						integer range 7 to 10;
		data_frame: 						integer := 8;
		
		metastable_filter_init_comm: 				boolean;
		metastable_filter_recover_fsm_n: 			boolean
	);
	
	port(
		SDA_in: 							in std_logic;
		SDA_out: 							out std_logic;
		SCL: 								inout std_logic;
		output_enable: 						out std_logic;
		runtime_speed_ctrl: 				in std_logic;
	
		clk: 								in std_logic;
		reset: 								in std_logic;
		
		init_comm: 							in std_logic;
		read_or_write: 						in std_logic;
		slave_address: 						in std_logic_vector(address_frame-1 downto 0);
		data_in: 							in std_logic_vector(data_frame-1 downto 0);
		data_out: 							out std_logic_vector(data_frame-1 downto 0);
		transfer_done: 						out std_logic;
		
		invalid_state_error:				out	std_logic;
		recover_fsm_n:						in	std_logic;
		recover_fsm_n_ack:					out	std_logic
	);
	
end entity i2c_transceiver;	

architecture rtl of i2c_transceiver is
	
	signal ff_reset:							std_logic;
	signal as_reset:							std_logic;
	
	signal ff_init_comm:						std_logic;
	signal init_comm_filtered:					std_logic;
	signal init_comm_internal:					std_logic;
	signal ff_recover_fsm_n:					std_logic;
	signal recover_fsm_n_filtered:				std_logic;
	signal recover_fsm_n_internal:				std_logic;
	
	type state_t is (	
		wait_for_input,
		change_config,
		transaction_start,
		addressing,
		data_transfer,
		error	
	);	
	signal state:								state_t;
	attribute syn_preserve: 					boolean;
	attribute syn_preserve of state:			signal is true;
	signal scl_count:							integer range 0 to 499;
	signal bit_count:							integer range 0 to 11;

	signal symbol_rate: 							integer range 100 to 400 := 100;
	signal clk_bus: 							integer := symbol_rate * 1000;
	

	signal ack_or_nack: 						boolean;
	
	
	
	-----------------------------------------
		-----------------------------------------
	-----------------------------------------
	begin
	RESET_SYNC: process ( clk, reset )
		begin
		if ( reset = '0' ) then
			ff_reset <= '0';
			as_reset <= '0';
		elsif ( rising_edge(clk) ) then
			ff_reset <= '1';
			as_reset <= ff_reset;
		end if;
	end process;
	
	METASTABLE_FILTER_BLOCK: process ( clk, as_reset )
		begin
		if ( as_reset = '0' ) then
			ff_init_comm <= '0';
			init_comm_filtered <= '0';
			ff_recover_fsm_n <= '1';
			recover_fsm_n_filtered <= '1';
		elsif ( rising_edge(clk) ) then
			ff_init_comm <= init_comm;
			init_comm_filtered <= ff_init_comm;
			ff_recover_fsm_n <= recover_fsm_n;
			recover_fsm_n_filtered <= ff_recover_fsm_n;
		end if;
	end process;
	
	L_METASTABLE_FILTER_BYPASS: block
		begin
		init_comm_internal <= init_comm_filtered when metastable_filter_init_comm = false else init_comm;
		recover_fsm_n_internal <= recover_fsm_n_filtered when metastable_filter_recover_fsm_n = false else recover_fsm_n;
	end block;
	
	L_METASTABLE_FILTER_ACKNOWLEDGE: block
		begin
		recover_fsm_n_ack <= recover_fsm_n_internal;
	end block;
	
	-----------------------------------------
		-----------------------------------------
	-----------------------------------------
	
	
	I2C_FSM: process ( clk, as_reset )
		begin
		if ( as_reset = '0' ) then
			state <= wait_for_input;
			transfer_done <= '1';
			output_enable <= '0';
			SDA_out <= '1';
			SCL <= '1';
			invalid_state_error <= '0';
			scl_count <= 0;
			bit_count <= 0;
			data_out <= X"00";
		
		elsif ( rising_edge(clk) ) then
			case state is
				when wait_for_input	=> 		if(runtime_speed_ctrl = '1') then
				state  <= change_config;
				elsif (init_comm = '1') then
					transfer_done <= '0';
					SDA_out <= '0';
					if(scl_count = (clk_in / clk_bus) - 1) then					--Wait a cycle--
						scl_count <= 0;
						state <= transaction_start;
					else
						scl_count <= scl_count + 1;
					end if;
				end if;
				
				when change_config => 			if(data_in(0) = '0') then
				symbol_rate <= 100;
				clk_bus <= symbol_rate * 1000;
				else
					symbol_rate <= 400;
					clk_bus <= symbol_rate * 1000;
				end if;
				state <= wait_for_input;
				
				when transaction_start => 		output_enable <= '1';
				SCL <= '0';
				if( scl_count = (clk_in / clk_bus) - 1 ) then						--Wait a cycle--
					scl_count <= 0;
				state <= addressing;
				else
					scl_count <= scl_count + 1;
				end if;
				
				when addressing =>			if(bit_count = address_frame + 2) then							--Acknowledged, proceed with data transfer--
					bit_count <= 0;
					if(ack_or_nack = false) then
					state <= error;
					else
						state <= data_transfer;
					end if;
					else
						if(bit_count = address_frame + 1) then						--R/W bit transferred, processing acknowledge bit--
							if(SDA_in = '1') then
							ack_or_nack <= false;
							else
								ack_or_nack <= true;
							end if;
						end if;
						if(bit_count = address_frame) then					--Addressing completed, transferring R/W bit--
							SDA_out <= read_or_write;
						end if;
						if(bit_count < address_frame) then
							SDA_out <= slave_address((address_frame - 1) - bit_count);		--Addressing, starting with MSB--
						end if;
						if(scl_count < ((clk_in / clk_bus) / 2) - 1) then			--CLK lower half--
							SCL <= '0';
						scl_count <= scl_count + 1;
						elsif(scl_count = (clk_in / clk_bus) - 1) then				--Bit transferred--
							scl_count <= 0;
						bit_count <= bit_count + 1;
						else															--CLK upper half--
							SCL <= '1';
							scl_count <= scl_count + 1;
						end if;
					end if;
					
					
					when data_transfer =>			if(bit_count = data_frame + 1) then							--Acknowledged--
						if(ack_or_nack = false) then
						state <= error;
						else
							bit_count <= 0;
							SDA_out <= '1';
							if(init_comm = '0') then						--Check if there is any further data to send / receive--
								output_enable <= '0';
								state <= wait_for_input;
							end if;
						end if;
						else
							if(bit_count = data_frame) then							--Transfer completed, proceeding with acknowledge--
								transfer_done <= '1';
								if(read_or_write = '0') then
								SDA_out <= '0';
								else
									if(SDA_in = '1') then
									ack_or_nack <= false;
									else
										ack_or_nack <= true;
									end if;
								end if;
								else
									if(read_or_write = '0') then
									data_out((data_frame - 1) - bit_count) <= SDA_in;			--Reading data from SDA line, MSB first--
									else
										SDA_out <= data_in((data_frame - 1) - bit_count);			--Writing data to SDA line, MSB first--
									end if;
								end if;
								if(scl_count < ((clk_in / clk_bus) / 2) - 1) then				--CLK lower half--
									SCL <= '0';
								scl_count <= scl_count + 1;
								elsif(scl_count = (clk_in / clk_bus) - 1) then					--Bit transferred--
									scl_count <= 0;
								bit_count <= bit_count + 1;
								else										--CLK upper half--
									SCL <= '1';
									scl_count <= scl_count + 1;
								end if;
						end if;
						
						when error => 					transfer_done <= '1';
														output_enable <= '0';
														SDA_out <= '1';
														SCL <= '1';
														scl_count <= 0;
														bit_count <= 0;
						
						if ( recover_fsm_n_internal = '0' ) then
							invalid_state_error <= '0';
							state <= wait_for_input;
						end if;
						
						when others => 					invalid_state_error <= '1';
						state <= error;
						
			end case;
		end if;
	end process;
	
	end architecture rtl;				
