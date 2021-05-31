library ieee;
use ieee.std_logic_1164.all;
---------------------------------------------------------------------------------------------------
entity i2c_slave_bfm is
	port(
		SDA_slave_input:								in std_logic;
		SDA_slave_output:								out std_logic;
		SCL_slave:										in std_logic;
		
		slave_data_2_send:								in	std_logic_vector (7 downto 0):= X"99";
		slave_data_received:							out	std_logic_vector (7 downto 0):= X"00"
		
		
	);
end entity i2c_slave_bfm;

---------------------------------------------------------------------------------------------------

architecture behavior of i2c_slave_bfm is
	
begin
	
	process
	begin
		
		
		wait until falling_edge(SDA_slave_input);
		wait until falling_edge(SCL_slave);
		
		for i in 7 downto 0 loop					--[7:1] = address, [0] = R/W bit
		wait until rising_edge(SCL_slave);
		slave_data_received(i) <= SDA_slave_input;
		end loop;
		wait until falling_edge(SCL_slave);
		
		if(slave_data_received = X"16") then
			wait until rising_edge(SCL_slave);
			SDA_slave_output <= '0';  				--address ack
			
			for j in 7 downto 0 loop				--[7:0] = data
				wait until rising_edge(SCL_slave);
				SDA_slave_output <= slave_data_2_send(j);
				
			end loop;
			wait until rising_edge(SCL_slave);
		elsif(slave_data_received = X"17") then
			wait until rising_edge(SCL_slave);
			SDA_slave_output <= '0';  				--address ack
			
			for j in 7 downto 0 loop				--[7:0] = data
				wait until rising_edge(SCL_slave);
				slave_data_received(j) <= SDA_slave_input;
				
			end loop;
			wait until rising_edge(SCL_slave);
			SDA_slave_output <= '0';  				--data ack
		else
			SDA_slave_output <= '1';  				--address nack
			end if;
			
		
	end process;
end architecture behavior;

			














