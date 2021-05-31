library ieee;
use ieee.std_logic_1164.all;
---------------------------------------------------------------------------------------------------
entity tb_acu_mmio_bfm is
end entity tb_acu_mmio_bfm;
---------------------------------------------------------------------------------------------------
architecture behavior of tb_acu_mmio_bfm is
	
	
	constant clk_period:           						time							:= 10 ns;
	type boolean_array_t 								is array (0 to 255) of boolean;
    signal trigger_signals: boolean_array_t 			:= ( others => false );
    signal check_done_signals: boolean_array_t			:= ( others => false );

	signal generate_read_cycle:							std_logic	 					:= '0';
	signal generate_write_cycle:						std_logic						:= '0';
	signal address:										std_logic_vector (15 downto 0) 	:= X"0000";
	signal data_2_write:								std_logic_vector (15 downto 0)	:= X"0000";
	signal data_read:									std_logic_vector (15 downto 0);
	signal busy:										std_logic;
	
	
	signal clk_i2c:										std_logic		:= '1';
	signal clk_bfm:										std_logic		:= '0';
	signal raw_reset_n:									std_logic		:= '1';
	signal acu_write_strobe:							std_logic;
	signal acu_read_strobe:								std_logic;
	signal i2c_ready:									std_logic;
	signal acu_address:									std_logic_vector (15 downto 0);
	signal acu_data:									std_logic_vector (15 downto 0);
	signal i2c_data:									std_logic_vector (15 downto 0);
	
	signal SDA_in:										std_logic := '1';
	signal SDA_out:										std_logic := '1';
	signal SCL:											std_logic := '1';
	signal OE:											std_logic := '0';

	signal acu2slave:									std_logic_vector (7 downto 0) := X"99";
	signal slave2acu:									std_logic_vector (7 downto 0);
	
begin
	 
	
	
	L_CLOCK_BFM: process
	begin
		wait for 40 ns;
		loop
			wait for 10 ns;
			clk_bfm <= not clk_bfm;
		end loop;
	end process;

	L_CLOCK_I2C: process
	begin
        wait for clk_period / 2;
        clk_i2c <= not clk_i2c;
    end process;

	L_ACU_MMIO_BFM:	entity work.acu_mmio_bfm(behavior)
						port map (
							generate_read_cycle						=> generate_read_cycle,
							generate_write_cycle					=> generate_write_cycle,
							address									=> address,
							data_2_write							=> data_2_write,
							data_read								=> data_read,
							busy									=> busy,
							clk										=> clk_bfm,
							write_strobe							=> acu_write_strobe,
							read_strobe								=> acu_read_strobe,
							dmem_ready								=> i2c_ready,
							address_2_dmem							=> acu_address,
							data_from_dmem							=> i2c_data,
							data_2_dmem								=> acu_data
						);
	
	
	
	L_ACU_MMIO_I2C_TRANSCEIVER:	entity work.acu_mmio_i2c_transceiver(rtl)
										generic map (
											metastable_filter_bypass_acu		=> false,
											metastable_filter_bypass_recover_fsm_n	=> true,
											
											clk_in									=> 50000000,
											address_frame							=> 7,
											data_frame								=> 8,
											
											address_init_comm						=> 3,
											address_data							=> 4,
											address_speed_ctrl						=> 5,
											
											address_slave_address					=> 6
										)
										
										port map (
											clk							=> clk_i2c,
											raw_reset_n					=> raw_reset_n,
											read_strobe_from_acu		=> acu_read_strobe,
											write_strobe_from_acu		=> acu_write_strobe,
											ready_2_acu					=> i2c_ready,
											address_from_acu			=> acu_address,
											data_from_acu				=> acu_data,
											data_2_acu					=> i2c_data,
											SDA_in							=> SDA_in,
											SDA_out							=> SDA_out,
											SCL							=> SCL,
											output_enable				=> OE,
											invalid_state_error			=> open,
											recover_fsm_n				=> '1',
											recover_fsm_n_ack			=> open
);

L_ACU_MMIO_I2C_TRANSCEIVER_SLAVE: entity work.i2c_slave_bfm(behavior)
						port map(
									
							SDA_slave_input								=> SDA_out,
							SDA_slave_output							=> SDA_in,
							
							SCL_slave								=> SCL,
							
							slave_data_2_send							=> acu2slave,
							slave_data_received							=> slave2acu
							
							);

	
										
	L_TEST_SEQUENCE: process
	begin
	
		
		trigger_signals(1) <= not trigger_signals(1);
		wait for 230 ns;
		raw_reset_n <= '0';
		wait for 450 ns;
		wait until falling_edge(clk_i2c);
		raw_reset_n <= '1';
		
		-- wait for checks to end
        loop
            if ( check_done_signals(1) = true ) then exit;
            else wait for 1 ns;
            end if;
        end loop;
		
		
		
		wait for 1 us;
		---------------------WRITE SLOW-----------------------
		address <= X"0004";			-- data
		data_2_write <= X"00AB";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0006";		-- slave_address
		data_2_write <= X"000B";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0003";		-- init_comm
		data_2_write <= X"0001";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 11 us;
		
		if(slave2acu = X"AB") then
			report "Successful slow write operation";
		else
			report "ERROR. Slow write operation failed";
			end if;
		
				--------------------READ SLOW-----------------------
		address <= X"0006";		-- slave_address
		data_2_write <= X"000B";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0003";		-- init_comm
		data_2_write <= X"0000";    ---read
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0004";		-- data
		generate_read_cycle <= '1';
		wait until falling_edge(busy);
		generate_read_cycle <= '0';

		wait for 11 us;
		
		if(data_read = X"0099") then
			report "Successful slow read operation";
		else
			report "ERROR. Slow read operation failed";
			end if;
		
		---------------------CHANGE TO FAST MODE-----------------------
		address <= X"0005";			-- change speed
		data_2_write <= X"0001";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';

		wait for 200 us;
			
		---------------------WRITE FAST-----------------------
		address <= X"0004";			-- data
		data_2_write <= X"00AA";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0006";		-- slave_address
		data_2_write <= X"000B";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0003";		-- init_comm
		data_2_write <= X"0001";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 200 us;
		
		if(slave2acu = X"AA") then
			report "Successful fast write operation";
		else
			report "ERROR. Fast write operation failed";
			end if;

		--------------------READ FAST-----------------------
		address <= X"0006";		-- slave_address
		data_2_write <= X"000B";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0003";		-- init_comm
		data_2_write <= X"0000";    ---read
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0004";		-- data
		generate_read_cycle <= '1';
		wait until falling_edge(busy);
		generate_read_cycle <= '0';

		wait for 11 us;
		
		if(data_read = X"0099") then
			report "Successful fast read operation";
		else
			report "ERROR. Fast read operation failed";
			end if;
			
		---------------------CHANGE BACK TO SLOW MODE-----------------------
		address <= X"0005";			-- change speed
		data_2_write <= X"0000";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';

		wait for 200 us;
			
		---------------------WRITE SLOW TO NON-EXISTING SLAVE, SHOULD RESULT IN ERROR-----------------------
		address <= X"0004";			-- data
		data_2_write <= X"00AB";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0006";		-- slave_address
		data_2_write <= X"000F";	--this slave is not connected, transceiver fsm should go to error after addressing
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 1 us;
		
		address <= X"0003";		-- init_comm
		data_2_write <= X"0001";
		generate_write_cycle <= '1';
		wait until falling_edge(busy);
		generate_write_cycle <= '0';
		
		wait for 11 us;
		
		if(SCL = '1') and (SDA_out = '1') and (OE = '0') then
			report "Expectations met";
		else
			report "ERROR. Unexpected behavior.";
			end if;
		
	
		wait;
	end process;
	
	 L_CHECKS: block
    begin
    
        -- check #1: The reset signal shall set SDA_out to 1 asynchronously
		process begin
			
			wait on trigger_signals(1)'transaction;
			wait until falling_edge(raw_reset_n);
			wait for clk_period / 2;
			
			if ( SDA_out = '1' and  SCL = '1' and OE = '0') then report "--------------------------------------------------------------------> check  #1 OK";				
			else report "--------------------------------------------------------------------> check  #1 FAIL";
			end if;
		
			check_done_signals(1) <= true;
			wait;
		end process;
	 end block L_CHECKS;

end architecture behavior;
---------------------------------------------------------------------------------------------------

