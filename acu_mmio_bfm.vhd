library ieee;
use ieee.std_logic_1164.all;
---------------------------------------------------------------------------------------------------
entity acu_mmio_bfm is
	port (
		-- Host interface
		generate_read_cycle:					in	std_logic;
		generate_write_cycle:					in	std_logic;
		address:								in	std_logic_vector (15 downto 0);
		data_2_write:							in	std_logic_vector (15 downto 0);
		data_read:								out	std_logic_vector (15 downto 0)		:= (others => '0');
		busy:									out	std_logic							:= '0';

		
		-- ACU MMIO master interface
		clk:                        	in  std_logic;
        write_strobe:               	out std_logic									:= '0';
        read_strobe:                	out std_logic									:= '0';
        dmem_ready:                 	in  std_logic;
        address_2_dmem:             	out std_logic_vector (15 downto 0)				:= (others => '0');
        data_from_dmem:             	in  std_logic_vector (15 downto 0);
        data_2_dmem:                	out std_logic_vector (15 downto 0)				:= (others => '0')
	);
end entity acu_mmio_bfm;
---------------------------------------------------------------------------------------------------
architecture behavior of acu_mmio_bfm is
begin

	
	
	-------------------------------------------------------
	-------------------------------------------------------
	-------------------------------------------------------

	L_MMIO_IF:	process
	begin
	
		wait until (rising_edge(generate_read_cycle) or rising_edge(generate_write_cycle));
		
		busy <= '1';
		
		if ( rising_edge(generate_read_cycle) ) then
			
			-- generate an MMIO read cycle...
			wait until rising_edge(clk);
			address_2_dmem <= address;
			read_strobe <= '1';
			wait until falling_edge(dmem_ready);
			wait until rising_edge(clk);
			read_strobe <= '0';
			wait until rising_edge(dmem_ready);
			wait until rising_edge(clk);
			data_read <= data_from_dmem;
			busy <= '0';
			
		else
		
			-- generate an MMIO write cycle...
			wait until rising_edge(clk);
			address_2_dmem <= address;
			data_2_dmem <= data_2_write;
			write_strobe <= '1';
			wait until falling_edge(dmem_ready);
			wait until rising_edge(clk);
			write_strobe <= '0';
			wait until rising_edge(dmem_ready);
			wait until rising_edge(clk);
			busy <= '0';
		
		end if;
	
	end process;

end architecture behavior;
---------------------------------------------------------------------------------------------------
