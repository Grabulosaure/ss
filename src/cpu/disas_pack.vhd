--------------------------------------------------------------------------------
-- TEM : TACUS
-- Assembleur/Désassembleur
--------------------------------------------------------------------------------
-- DO 4/2009
--------------------------------------------------------------------------------

--##############################################################################
--## This source file is copyrighted. Read the "lic.txt" file before use.     ##
--## Experimental version. No warranty of any sort. All rights reserved.      ##
--##############################################################################

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.iu_pack.ALL;

PACKAGE disas_pack IS

  FUNCTION disassemble (
    CONSTANT op          : IN uv32;
    CONSTANT pc          : IN uv32
    ) RETURN string;
  
  PROCEDURE copie (
    SIGNAL   o : OUT string(1 TO 50);
    CONSTANT i : IN  string);
  
  FUNCTION trap_decode (
    CONSTANT t : type_trap)
    RETURN string;
  
  --pragma synthesis_off
  FUNCTION assemble (
    CONSTANT code : string)
    RETURN unsigned;

  FUNCTION imm22 (
    CONSTANT val : uv32)
    RETURN string;
  
  FUNCTION simm13 (
    CONSTANT val : uv32)
    RETURN string;
  
  FUNCTION imm12 (
    CONSTANT val : uv32)
    RETURN string;

  FUNCTION branch_calc (
    CONSTANT src  : natural;
    CONSTANT dest : natural)
    RETURN string;
  --pragma synthesis_on
  
END PACKAGE disas_pack;
--------------------------------------------------------------------------------

PACKAGE BODY disas_pack IS

  --############################################################################
  -- Désassembleur
  TYPE arr_name IS ARRAY(natural RANGE <>) OF string(1 TO 4);

  CONSTANT IREG : arr_name(0 TO 31) := (
    "(0) ","%g1 ","%g2 ","%g3 ","%g4 ","%g5 ","%g6 ","%g7 ",
    "%o0 ","%o1 ","%o2 ","%o3 ","%o4 ","%o5 ","%sp ","%o7 ",
    "%l0 ","%l1 ","%l2 ","%l3 ","%l4 ","%l5 ","%l6 ","%l7 ",
    "%i0 ","%i1 ","%i2 ","%i3 ","%i4 ","%i5 ","%fp ","%i7 ");
  
  CONSTANT FREG : arr_name(0 TO 31) := (
    "%f0 ","%f1 ","%f2 ","%f3 ","%f4 ","%f5 ","%f6 ","%f7 ",
    "%f8 ","%f9 ","%f10","%f11","%f12","%f13","%f14","%f15",
    "%f16","%f17","%f18","%f19","%f20","%f21","%f22","%f23",
    "%f24","%f25","%f26","%f27","%f28","%f29","%f30","%f31");
  
  --------------------------------------
  TYPE arr_cond IS ARRAY(natural RANGE <>) OF string(1 TO 5);
  CONSTANT ICOND : arr_cond(0 TO 31) := (
    "N    ","E    ","LE   ","L    ","LEU  ","CS   ","NEG  ","VS   ",
    "A    ","NE   ","G    ","GE   ","GU   ","CC   ","POS  ","VC   ",
    "N,A  ","E,A  ","LE,A ","L,A  ","LEU,A","CS,A ","NEG,A","VS,A ",
    "A,A  ","NE,A ","G,A  ","GE,A ","GU,A ","CC,A ","POS,A","VC,A ");

  CONSTANT FCOND : arr_cond(0 TO 31) := (
    "N    ","NE   ","LG   ","UL   ","L    ","UG   ","G    ","U    ",
    "A    ","E    ","UE   ","GE   ","UGE  ","LE   ","ULE  ","O    ",
    "N,A  ","NE,A ","LG,A ","UL,A ","L,A  ","UG,A ","G,A  ","U,A  ",
    "A,A  ","E,A  ","UE,A ","GE,A ","UGE,A","LE,A ","ULE,A","O,A  ");
  --------------------------------------

  FUNCTION str_ireg (
    v : unsigned(4 DOWNTO 0))
    RETURN string IS
  BEGIN
    RETURN IREG(to_integer(v));
  END FUNCTION str_ireg;
  
  FUNCTION str_freg (
    v : unsigned(4 DOWNTO 0))
    RETURN string IS
  BEGIN
    RETURN FREG(to_integer(v));
  END FUNCTION str_freg;

  FUNCTION rspido (op : uv32)
    RETURN string IS
    VARIABLE v : integer RANGE -10000 TO 10000;
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
  BEGIN
    v:=to_integer(signed(op_simm13));
     IF op_imm='1' THEN
       IF v=0 THEN     RETURN str_ireg(op_rs1);
       ELSIF v>0 THEN  RETURN str_ireg(op_rs1) & "+ " & integer'image(v);
       ELSIF v<0 THEN  RETURN str_ireg(op_rs1) & "- " & integer'image(-v);
       ELSE
         REPORT "Port'nawak" SEVERITY failure;
         RETURN "C'est foutu";
       END IF;
    ELSE
      IF op_rs1/="00000" AND op_rs2/="00000" THEN
        RETURN str_ireg(op_rs1) & "+ " & str_ireg(op_rs2);
      ELSIF op_rs1/="00000" THEN
        RETURN str_ireg(op_rs1);
      ELSIF op_rs2/="00000" THEN
        RETURN str_ireg(op_rs2);
      ELSE
        RETURN "0";
      END IF;
    END IF;
  END rspido;
  
  --------------------------------------
  FUNCTION disas_arith (
    op : uv32;
    co : string(1 TO 8))
    RETURN string IS
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
  BEGIN
    IF op_imm='1' THEN
      -- Immédiat
      RETURN co & str_ireg(op_rs1) & ", " &
        integer'image(to_integer(signed(op_simm13))) & "," &
        str_ireg(op_rd);
    ELSE
      -- Registres
      RETURN co & str_ireg(op_rs1) & "," & str_ireg(op_rs2) & "," &
        str_ireg(op_rd);
    END IF;
  END FUNCTION disas_arith;
  
   --------------------------------------
  FUNCTION disas_comp (
    op : uv32;
    co : string(1 TO 8))
    RETURN string IS
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
  BEGIN
    IF op_imm='1' THEN
      -- Immédiat
      RETURN co & str_ireg(op_rs1) & ", " &
        integer'image(to_integer(signed(op_simm13)));
    ELSE
      -- Registres
      RETURN co & str_ireg(op_rs1) & "," & str_ireg(op_rs2);
    END IF;
  END FUNCTION disas_comp;
  
  --------------------------------------
  FUNCTION disas_mov (
    op : uv32;
    co : string(1 TO 8))
    RETURN string IS
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
  BEGIN
    IF op_imm='1' THEN
      -- Immédiat
      RETURN co & integer'image(to_integer(signed(op_simm13))) & "," &
        str_ireg(op_rd);
    ELSE
      -- Registres
      RETURN co & str_ireg(op_rs2) & "," & str_ireg(op_rd);
    END IF;
  END FUNCTION disas_mov;
  
 --------------------------------------
  FUNCTION disas_jmpl (op : uv32)
    RETURN string IS
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
  BEGIN
    -- JMP address  = JMPL address,%g0
    -- CALL address = JMPL address,%o7
    -- RET          = JMPL %i7+8,%g0
    -- RETL         = JMPL %o7+8,%g0
    IF to_integer(op_rd)=0 AND to_integer(op_rs1)=31 -- I7
      AND to_integer(op_simm13)=8 THEN
      RETURN "RET     ";
    ELSIF to_integer(op_rd)=0 AND to_integer(op_rs1)=15 -- O7
      AND to_integer(op_simm13)=8 THEN
      RETURN "RETL    ";
    ELSIF to_integer(op_rd)=0 THEN
      RETURN "JMP     " & rspido(op);
    ELSIF to_integer(op_rd)=15 THEN  -- O7
      RETURN "CALL    " & rspido(op);
    ELSE
      RETURN "JMPL    " & rspido(op) & "," & str_ireg(op_rd);
    END IF;
  END FUNCTION disas_jmpl;
  
  --------------------------------------
  FUNCTION disas_ticc (op : uv32)
    RETURN string IS
    VARIABLE t : uv8;
    ALIAS op_annul : std_logic IS op(29);
    ALIAS op_cnd : unsigned(28 DOWNTO 25) IS op(28 DOWNTO 25);
  BEGIN
    RETURN "T" & ICOND(to_integer(op_annul & op_cnd)) & "  " & rspido(op);
    -- Attention, cas particuliers, codes opératoires pour SparcV9
  END FUNCTION disas_ticc;
  
  --------------------------------------
  FUNCTION disas_shift (
    op : uv32;
    co : string(1 TO 8))
    RETURN string IS
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
    ALIAS op_imm : std_logic IS op(13);
  BEGIN
    IF op_imm='1' THEN
      -- Immédiat
      RETURN co & str_ireg(op_rs1) & ", " &
        natural'image(to_integer(op_rs2)) & "," & str_ireg(op_rd);
    ELSE
      -- Registres
      RETURN co & str_ireg(op_rs1) & "," & str_ireg(op_rs2) & "," &
        str_ireg(op_rd);
    END IF;
  END FUNCTION disas_shift;
  
  --------------------------------------
  FUNCTION disas_wrspr (
    op : uv32;
    reg: string)
    RETURN string IS
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
    ALIAS op_imm : std_logic IS op(13);
    ALIAS op_simm13 : unsigned(12 DOWNTO 0) IS op(12 DOWNTO 0);
  BEGIN
    IF op_imm='1' THEN
      -- Immédiat
      RETURN "WR " & str_ireg(op_rs1) & ", " &
        integer'image(to_integer(signed(op_simm13))) & "," & reg;
    ELSE
      -- Registres
      RETURN "WR " & str_ireg(op_rs1) & "," & str_ireg(op_rs2) & "," &
        reg;
    END IF;
  END FUNCTION disas_wrspr;
  
  --------------------------------------
  FUNCTION disas_fpop1 (op : uv32)
    RETURN string IS
    ALIAS op_opf : unsigned(13 DOWNTO 5) IS op(13 DOWNTO 5);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
  BEGIN
    -- OP3 = 110100
    CASE op_opf IS
      WHEN "011000100" =>               -- FiTOs
        RETURN "FiTOs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011001000" =>               -- FiTOd
        RETURN "FiTOd   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011001100" =>               -- FiTOq
        RETURN "FiTOq   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
        
      WHEN "011010001" =>               -- FsTOi
        RETURN "FsTOi   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011010010" =>               -- FdTOi
        RETURN "FdTOi   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011010011" =>               -- FqTOi
        RETURN "FqTOi   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
        
      WHEN "011001001" =>               -- FsTOd
        RETURN "FsTOd   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011001101" =>               -- FsTOq
        RETURN "FsTOq   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011000110" =>               -- FdTOs
        RETURN "FdTOs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011001110" =>               -- FdTOq
        RETURN "FdTOq   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011000111" =>               -- FqTOs
        RETURN "FqTOs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "011001011" =>               -- FqTOd
        RETURN "FqTOd   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
        
      WHEN "000000001" =>               -- FMOVs
        RETURN "FMOVs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "000000101" =>               -- FNEGs
        RETURN "FNEGs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "000001001" =>               -- FABSs
        RETURN "FABSs   " & str_freg(op_rs2) & ", " & str_freg(op_rd);
        
      WHEN "000101001" =>               -- FSQRTs
        RETURN "FSQRTs  " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "000101010" =>               -- FSQRTd
        RETURN "FSQRTd  " & str_freg(op_rs2) & ", " & str_freg(op_rd);
      WHEN "000101011" =>               -- FSQRTq
        RETURN "FSQRTq  " & str_freg(op_rs2) & ", " & str_freg(op_rd);
        
      WHEN "001000001" =>               -- FADDs
        RETURN "FADDs   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001000010" =>               -- FADDd
        RETURN "FADDd   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001000011" =>               -- FADDq
        RETURN "FADDq   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001000101" =>               -- FSUBs
        RETURN "FSUBs   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001000110" =>               -- FSUBd
        RETURN "FSUBd   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001000111" =>               -- FSUBq
        RETURN "FSUBq   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
        
      WHEN "001001001" =>               -- FMULs
        RETURN "FMULs   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001001010" =>               -- FMULd
        RETURN "FMULd   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001001011" =>               -- FMULq
        RETURN "FMULq   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
        
      WHEN "001101001" =>               -- FsMULd
        RETURN "FsMULd  " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001101110" =>               -- FdMULq
        RETURN "FdMULq  " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
        
      WHEN "001001101" =>               -- FDIVs
        RETURN "FDIVs   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001001110" =>               -- FDIVd
        RETURN "FDIVd   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
      WHEN "001001111" =>               -- FDIVq
        RETURN "FDIVq   " & str_freg(op_rs1) & ", " & str_freg(op_rs2)
          & ", " & str_freg(op_rd);
        
      WHEN OTHERS =>
        RETURN "FPop1 invalide";
    END CASE;
  END FUNCTION disas_fpop1;
  
  --------------------------------------
  FUNCTION disas_fpop2 (op : uv32)
    RETURN string IS
    ALIAS op_opf : unsigned(13 DOWNTO 5) IS op(13 DOWNTO 5);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_rs2 : unsigned(4 DOWNTO 0) IS op(4 DOWNTO 0);
  BEGIN
    -- OP3 = 110101
    CASE op_opf IS
      WHEN "001010001" =>               -- FCMPs
        RETURN "FCMPs   " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      WHEN "001010010" =>               -- FCMPd
        RETURN "FCMPd   " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      WHEN "001010011" =>               -- FCMPq
        RETURN "FCMPq   " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      
      WHEN "001010101" =>               -- FCMPEs
        RETURN "FCMPEs  " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      WHEN "001010110" =>               -- FCMPEd
        RETURN "FCMPEd  " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      WHEN "001010111" =>               -- FCMPEq
        RETURN "FCMPEq  " & str_freg(op_rs1) & ", " & str_freg(op_rs2);
      
      WHEN OTHERS =>
        RETURN "FPop2 invalide";
    END CASE;
    
  END FUNCTION disas_fpop2;
  
  --------------------------------------
  FUNCTION disas_invalide (op : uv32)
    RETURN string IS
  BEGIN
    RETURN "<INVALIDE : " & To_HString(op) & " >";
  END FUNCTION disas_invalide;
  
  --------------------------------------
  FUNCTION disas_invalide (
    op : uv32;
    co : string)
    RETURN string IS
  BEGIN
    RETURN co;
  END FUNCTION disas_invalide;
  
  --############################################################################
  -- Opérations arithmético/logiques
  FUNCTION disas_alu (
    CONSTANT op          : IN  uv32; -- Fetch
    CONSTANT pc          : IN  uv32
    ) RETURN string IS
    ALIAS op_rs1 : unsigned(18 DOWNTO 14) IS op(18 DOWNTO 14);
    ALIAS op_op3 : unsigned(24 DOWNTO 19) IS op(24 DOWNTO 19);
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
  BEGIN
    
    CASE op_op3 IS
      WHEN "000000" =>                  -- ADD
        RETURN disas_arith(op,"ADD     ");
        
      WHEN "000001" =>                  -- AND
        RETURN disas_arith(op,"AND     ");
        
      WHEN "000010" =>                  -- OR
        IF op_rs1/="00000" THEN
          RETURN disas_arith(op,"OR      ");
        ELSE
          RETURN disas_mov  (op,"MOV     ");
        END IF;
        
      WHEN "000011" =>                  -- XOR
        RETURN disas_arith(op,"XOR     ");
        
      WHEN "000100" =>                  -- SUB
        RETURN disas_arith(op,"SUB     ");
        
      WHEN "000101" =>                  -- ANDN
        RETURN disas_arith(op,"ANDN    ");
        
      WHEN "000110" =>                  -- ORN
        RETURN disas_arith(op,"ORN     ");
        
      WHEN "000111" =>                  -- XNOR
        RETURN disas_arith(op,"XNOR    ");
        
      WHEN "001000" =>                  -- ADDX
        RETURN disas_arith(op,"ADDX    ");
        
      WHEN "001001" =>                  -- SparcV9 : Multiply
        RETURN disas_invalide(op);
        
      WHEN "001010" =>                  -- UMUL
        RETURN disas_arith(op,"UMUL    ");
        
      WHEN "001011" =>                  -- SMUL
        RETURN disas_arith(op,"SMUL    ");
        
      WHEN "001100" =>                  -- SUBX
        RETURN disas_arith(op,"SUBX    ");
        
      WHEN "001101" =>                  -- Sparc V9 : Divide
        RETURN disas_invalide(op);
        
      WHEN "001110" =>                  -- UDIV
        RETURN disas_arith(op,"UDIV    ");
        
      WHEN "001111" =>                  -- SDIV
        RETURN disas_arith(op,"SDIV    ");
        
      WHEN "010000" =>                  -- ADDcc
        RETURN disas_arith(op,"ADDcc   ");
        
      WHEN "010001" =>                  -- ANDcc
        RETURN disas_arith(op,"ANDcc   ");
        
      WHEN "010010" =>                  -- ORcc
        RETURN disas_arith(op,"ORcc    ");
        
      WHEN "010011" =>                  -- XORcc
        RETURN disas_arith(op,"XORcc   ");
        
      WHEN "010100" =>                  -- SUBcc
        IF op_rd/="00000" THEN
          RETURN disas_arith(op,"SUBcc   ");
        ELSE
          RETURN disas_comp (op,"CMPcc   ");
        END IF;
        
      WHEN "010101" =>                  -- ANDNcc
        RETURN disas_arith(op,"ANDNcc  ");
        
      WHEN "010110" =>                  -- ORNcc
        RETURN disas_arith(op,"ORNcc   ");
        
      WHEN "010111" =>                  -- XNORcc
        RETURN disas_arith(op,"XNORcc  ");
        
      WHEN "011000" =>                  -- ADDXcc
        RETURN disas_arith(op,"ADDXcc  ");
        
      WHEN "011001" =>                  -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "011010" =>                  -- UMULcc
        RETURN disas_arith(op,"UMULcc  ");
        
      WHEN "011011" =>                  -- SMULcc
        RETURN disas_arith(op,"SMULcc  ");
        
      WHEN "011100" =>                  -- SUBXcc
        RETURN disas_arith(op,"SUBXcc  ");
        
      WHEN "011101" =>                  -- Sparc V8E : DIVScc
        RETURN disas_arith(op,"DIVScc  ");
        
      WHEN "011110" =>                  -- UDIVcc
        RETURN disas_arith(op,"UDIVcc  ");
        
      WHEN "011111" =>                  -- SDIVcc
        RETURN disas_arith(op,"SDIVcc  ");
        
      WHEN "100000" =>                  -- TADDcc
        RETURN disas_arith(op,"TADDcc  ");
        
      WHEN "100001" =>                  -- TSUBcc
        RETURN disas_arith(op,"TSUBcc  ");
        
      WHEN "100010" =>                  -- TADDccTV
        RETURN disas_arith(op,"TADDccTV");
        
      WHEN "100011" =>                  -- TSUBccTV
        RETURN disas_arith(op,"TSUBccTV");
        
      WHEN "100100" =>                  -- MULScc : Multiply Step
        RETURN disas_arith(op,"MULScc  ");
        
      WHEN "100101" =>                  -- SLL
        RETURN disas_shift(op,"SLL     ");
        
      WHEN "100110" =>                  -- SRL
        RETURN disas_shift(op,"SRL     ");
        
      WHEN "100111" =>                  -- SRA
        RETURN disas_shift(op,"SRA     ");
        
      WHEN "101000" =>                  -- RDY
        RETURN "RD " & "%y" & "," & str_ireg(op_rd);
        
      WHEN "101001" =>                  -- RDPSR (PRIV)
        RETURN "RD " & "%psr" & "," & str_ireg(op_rd);
        
      WHEN "101010" =>                  -- RDWIM (PRIV)
        RETURN "RD " & "%wim" & "," & str_ireg(op_rd);
        
      WHEN "101011" =>                  -- RDTBR (PRIV)      
        RETURN "RD " & "%tbr" & "," & str_ireg(op_rd);
        
      WHEN "101100" =>                  -- Sparc V9 : Move Integer Condition
        RETURN disas_invalide(op);
        
      WHEN "101101" =>                  -- Sparc V9 : Signed Divide 64bits
        RETURN disas_invalide(op);
        
      WHEN "101110" =>                  -- Sparc V9 : Population Count
        RETURN disas_invalide(op);
        
      WHEN "101111" =>                  -- Sparc V9 : Move Integer Condition
        RETURN disas_invalide(op);
        
      WHEN "110000" =>                  -- WRASR/WRY
        RETURN disas_wrspr(op,"%y");
        
      WHEN "110001" =>                  -- WRPSR (PRIV)
        RETURN disas_wrspr(op,"%psr");
        
      WHEN "110010" =>                  -- WRWIM (PRIV)
        RETURN disas_wrspr(op,"%wim");
        
      WHEN "110011" =>                  -- WRTBR (PRIV)
        RETURN disas_wrspr(op,"%tbr");
        
      WHEN "110100" =>                  -- FPOP1
        RETURN disas_fpop1(op);
        
      WHEN "110101" =>                  -- FPOP2
        RETURN disas_fpop2(op);
        
      WHEN "110110" =>                  -- CPOP1
        RETURN disas_invalide(op,"CPOP1");
        
      WHEN "110111" =>                  -- CPOP2
        RETURN disas_invalide(op,"CPOP2");
        
      WHEN "111000" =>                  -- JMPL : Jump And Link
        RETURN disas_jmpl(op);
        
      WHEN "111001" =>                  -- RETT (PRIV)
        RETURN "RETT    " & rspido(op);
        
      WHEN "111010" =>                  -- Ticc (B.27)
        RETURN disas_ticc(op);
        
      WHEN "111011" =>                  -- IFLUSH
        RETURN "IFLUSH  " & rspido(op);
        
      WHEN "111100" =>                  -- SAVE (B.20)
        RETURN disas_arith(op,"SAVE    ");
        
      WHEN "111101" =>                  -- RESTORE (B.20)
        RETURN disas_arith(op,"RESTORE ");
        
      WHEN "111110" =>                  -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "111111" =>                  -- Invalide
        RETURN disas_invalide(op);
        
      WHEN OTHERS =>
        RETURN "disas_alu : Erreur";
    END CASE;
    
  END FUNCTION disas_alu;
  
  --------------------------------------
  -- Opérations load/store unit
  FUNCTION disas_lsu (
    CONSTANT op          : IN uv32; -- Fetch
    CONSTANT pc          : IN uv32
    ) RETURN string IS
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_op3 : unsigned(24 DOWNTO 19) IS op(24 DOWNTO 19);
    ALIAS op_asi : unsigned(12 DOWNTO 5) IS op(12 DOWNTO 5);
  BEGIN
    CASE op_op3 IS
      WHEN "000000" =>        -- LD : Load Word
        RETURN "LD      " & "[" & rspido(op) & "]," & str_ireg(op_rd);
          
      WHEN "000001" =>        -- LDUB : Load Unsigned Byte
        RETURN "LDUB    " & "[" & rspido(op) & "]," & str_ireg(op_rd);
        
      WHEN "000010" =>        -- LDUH : Load Unsigned Half Word
        RETURN "LDUH    " & "[" & rspido(op) & "]," & str_ireg(op_rd);
        
      WHEN "000011" =>        -- LDD : Load DoubleWord
        RETURN "LDD     " & "[" & rspido(op) & "]," & str_ireg(op_rd);
        
      WHEN "000100" =>        -- ST
        RETURN "ST      " & str_ireg(op_rd) & ",[" & rspido(op) & "]";
       
      WHEN "000101" =>        -- STB
        RETURN "STB     " & str_ireg(op_rd) & ",[" & rspido(op) & "]";
       
      WHEN "000110" =>        -- STH
        RETURN "STH     " & str_ireg(op_rd) & ",[" & rspido(op) & "]";
 
      WHEN "000111" =>        -- STD
         RETURN "STD     " & str_ireg(op_rd) & ",[" & rspido(op) & "]";
         
      WHEN "001000" =>        -- SparcV9 : LDSW : Load Signed Word
        RETURN disas_invalide(op);
         
      WHEN "001001" =>        -- LDSB : Load Signed Byte
        RETURN "LDSB    " & "[" & rspido(op) & "]," & str_ireg(op_rd);
         
      WHEN "001010" =>        -- LDSH : Load Signed Half Word
        RETURN "LDSH    " & "[" & rspido(op) & "]," & str_ireg(op_rd);
         
      WHEN "001011" =>        -- SparcV9 : LDX : Load Extended Word : 64bits
        RETURN disas_invalide(op);
         
      WHEN "001100" =>        -- Invalide
        RETURN disas_invalide(op);
 
      WHEN "001101" =>        -- LDSTUB : Atomic Load/Store Unsigned Byte
        RETURN "LDSTUB  " & "[" & rspido(op) & "]," & str_ireg(op_rd);
         
      WHEN "001110" =>        -- SparcV9 : STX : Store Extended Word : 64bits
        RETURN disas_invalide(op);
       
      WHEN "001111" =>        -- SWAP : Swap register with Memory
        RETURN "SWAP    " & "[" & rspido(op) & "]," & str_ireg(op_rd);
         
      WHEN "010000" =>        -- LDA : Load Word from Alternate Space (PRIV)
        RETURN "LDA     " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
         
      WHEN "010001" =>        -- LDUBA : Load Unsigned Byte from Alternate Space
        RETURN "LDUBA   " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
         
      WHEN "010010" =>        -- LDUHA : Load Unsigned HalfWord from Alt. Space
        RETURN "LDUHA   " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
        
      WHEN "010011" =>        -- LDDA : Load DoubleWord from Alternate Space (PRIV)
        RETURN "LDDA    " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);

      WHEN "010100" =>        -- STA : Store Word into Alternate Space (PRIV)
        RETURN "STA     " & str_ireg(op_rd) & ",[" & rspido(op) & "] " & To_HString(op_asi);
       
      WHEN "010101" =>        -- STBA : Store Byte into Alternate Space (PRIV)
        RETURN "STBA    " & str_ireg(op_rd) & ",[" & rspido(op) & "] " & To_HString(op_asi);
      
      WHEN "010110" =>        -- STHA : Store Half Word into Alternate Space (PRIV)
        RETURN "STHA    " & str_ireg(op_rd) & ",[" & rspido(op) & "] " & To_HString(op_asi);
      
      WHEN "010111" =>        -- STDA : Store DoubleWord into Alternate Space (PRIV)
        RETURN "STDA    " & str_ireg(op_rd) & ",[" & rspido(op) & "] " & To_HString(op_asi);
      
      WHEN "011000" =>        -- SparcV9 : LDSWA : Load Signed Word into Alternate Space
        RETURN disas_invalide(op);
      
      WHEN "011001" =>        -- LDSBA : Load Signed Byte from Alternate Space (PRIV)
        RETURN "LDSBA   " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
      
      WHEN "011010" =>        -- LDSHA : Load Signed Half Word from Alternate Space (PRIV)
        RETURN "LDSHA   " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
        
      WHEN "011011" =>        -- SparcV9 : LDXA : Load Extended Word from Alternate Space : 64bit
        RETURN disas_invalide(op);

      WHEN "011100" =>        -- Invalide
        RETURN disas_invalide(op);

      WHEN "011101" =>        -- LDSTUBA : Atomic Load/Store Unsigned Byte in Alt. Space (PRIV)
        RETURN "LDSTUBA " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
        
      WHEN "011110" =>        -- SparcV9 : STXA : Store Extended Word fro Alternate Space : 64bits
        RETURN disas_invalide(op);
      
      WHEN "011111" =>        -- SWAPA : Swap register with memory in Alternate Space (PRIV)
        RETURN "SWAPA   " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
        
      WHEN "100000" =>        -- LDF : Load Floating Point
        RETURN "LDF     " & "[" & rspido(op) & "]," & str_freg(op_rd);
      
      WHEN "100001" =>        -- LDFSR : Load Floating Point State Register
        RETURN "LDFSR   " & "[" & rspido(op) & "], %fsr";
        
      WHEN "100010" =>        -- SparcV9 : LDQF : Load Quad Floating Point
        RETURN disas_invalide(op);
      
      WHEN "100011" =>        -- LDDF : Load Double Floating Point
        RETURN "LDDF    " & "[" & rspido(op) & "]," & str_freg(op_rd);
      
      WHEN "100100" =>        -- STF : Store Floating Point
        RETURN "STF     " & str_freg(op_rd) & ",[" & rspido(op) & "]"; 
    
      WHEN "100101" =>        -- STFSR : Store Floating Point State Register
        RETURN "STFSR   %fsr ,[" & rspido(op) & "]"; 
     
      WHEN "100110" =>        -- STDFQ : Store Double Floating Point Queue (PRIV)
        RETURN "STDFQ   %fq ,[" & rspido(op) & "]";
      
      WHEN "100111" =>        -- STDF : Store Double Floating Point
        RETURN "STDF    " & str_freg(op_rd) & ",[" & rspido(op) & "]"; 
    
      WHEN "101000" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101001" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101010" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101011" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101100" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101101" =>        -- SparcV9 : PREFETCH
        RETURN disas_invalide(op);

      WHEN "101110" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "101111" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "110000" =>        -- LDC : Load Coprocessor
        RETURN "LDC     " & " Coprocessor ?";
      
      WHEN "110001" =>        -- LDCSR : Load Coprocessor State Register
        RETURN "LDCSR   " & " Coprocessor ?";
       
      WHEN "110010" =>        -- Invalide
        RETURN disas_invalide(op);

      WHEN "110011" =>        -- LDDC : Load Double Coprocessor
        RETURN "LDDC    " & " Coprocessor ?";
       
      WHEN "110100" =>        -- STC : Store Coprocessor
        RETURN "STC     " & " Coprocessor ?";
     
      WHEN "110101" =>        -- STCSR : Store Coprocessor State Register
        RETURN "STCSR   " & " Coprocessor ?";
      
      WHEN "110110" =>        -- STDCQ : Store Double Coprocessor Queue
        RETURN "STDCQ   " & " Coprocessor ?";
       
      WHEN "110111" =>        -- STDC : Store Double Coprocessor
        RETURN "STDC    " & " Coprocessor ?";

      WHEN "111000" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "111001" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "111010" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "111011" =>        -- Invalide
        RETURN disas_invalide(op);

      WHEN "111100" =>        -- CASA : Compare and Swap. SparcV9/LEON (PRIV)
        RETURN "CASA    " & "[" & rspido(op) &  "] " & To_HString(op_asi) & "," & str_ireg(op_rd);
      
      WHEN "111101" =>        -- Invalide
        RETURN disas_invalide(op);

      WHEN "111110" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN "111111" =>        -- Invalide
        RETURN disas_invalide(op);
        
      WHEN OTHERS =>
        RETURN "disas_lsu : Erreur";
    END CASE;

  END FUNCTION disas_lsu;
  
  --------------------------------------
  -- Instruction CALL
  FUNCTION disas_call (
    CONSTANT op          : IN uv32;
    CONSTANT pc          : IN uv32
    ) RETURN string IS
    VARIABLE v : uv32;
    ALIAS op_disp30 : unsigned(29 DOWNTO 0) IS op(29 DOWNTO 0);
  BEGIN
    v:=pc+(op_disp30 & "00");
    RETURN "CALL    " & To_HString(v);
  END FUNCTION disas_call;
  
  --------------------------------------
  -- Instruction Bicc
  FUNCTION disas_bicc (
    CONSTANT op          : IN  uv32;
    CONSTANT pc          : IN  uv32
    ) RETURN string IS
    VARIABLE v : uv32;
    ALIAS op_annul : std_logic IS op(29);
    ALIAS op_cnd   : unsigned(28 DOWNTO 25) IS op(28 DOWNTO 25);
    ALIAS op_imm22 : unsigned(21 DOWNTO 0) IS op(21 DOWNTO 0);
  BEGIN
    v:=pc+sext(op_imm22 & "00",32);
    RETURN "B" & ICOND(to_integer(op_annul & op_cnd)) & "  " & To_HString(v);
  END FUNCTION disas_bicc;
  
  --------------------------------------
  -- Instruction FBfcc
  FUNCTION disas_fbfcc (
    CONSTANT op          : IN uv32;
    CONSTANT pc          : IN uv32
    ) RETURN string IS
    VARIABLE v : uv32;
    ALIAS op_annul : std_logic IS op(29);
    ALIAS op_cnd   : unsigned(28 DOWNTO 25) IS op(28 DOWNTO 25);
    ALIAS op_imm22 : unsigned(21 DOWNTO 0) IS op(21 DOWNTO 0);
  BEGIN
    v:=pc+sext(op_imm22 & "00",32);
    RETURN "FB" & FCOND(to_integer(op_annul & op_cnd)) & " " & To_HString(v);
  END FUNCTION disas_fbfcc;
  
  FUNCTION pad (
    CONSTANT s : IN string)
    RETURN string IS
    VARIABLE u : string(1 TO 42):=(OTHERS =>' ');
  BEGIN
    u(1 TO s'length):=s;
    RETURN u;
  END FUNCTION pad;
  
  --------------------------------------
  -- Désassemblage d'une instruction
  FUNCTION disassemble (
    CONSTANT op          : IN  uv32;   -- Opcode
    CONSTANT pc          : IN  uv32    -- Program Counter (pour calculs sauts relatifs)
    ) RETURN string IS
    ALIAS op_op  : unsigned(31 DOWNTO 30) IS op(31 DOWNTO 30);    
    ALIAS op_rd  : unsigned(29 DOWNTO 25) IS op(29 DOWNTO 25);
    ALIAS op_op2 : unsigned(24 DOWNTO 22) IS op(24 DOWNTO 22);
    ALIAS op_imm22 : unsigned(21 DOWNTO 0) IS op(21 DOWNTO 0);
  BEGIN
    --pragma synthesis_off
    IF 0=1 THEN
    --pragma synthesis_on
      RETURN "";
    --pragma synthesis_off
    ELSE
    CASE op_op IS
      WHEN "00" =>
        CASE op_op2 IS
          WHEN "000" =>       -- UNIMP : Unimplemented instruction
            RETURN pad("UNIMP   " & To_HString("00" & op_imm22));
            
          WHEN "001" =>       -- SparcV9 BPcc : Integer Conditional Branch with Prediction
            RETURN pad(disas_invalide(op));
            
          WHEN "010" =>       -- Bicc : Integer Conditional Branch
            RETURN pad(disas_bicc(op,pc));
            
          WHEN "011" =>       -- SparcV9 : BPr
            RETURN pad(disas_invalide(op));
            
          WHEN "100" =>       -- SETHI : Set High 22 bits of register
            IF op_imm22=0 AND op_rd=0 THEN
              RETURN pad("NOP     ");  --NOP = SETHI 0,g0
            ELSE
              RETURN pad("SETHI   x" & To_HString(op_imm22 & "0000000000") &
                " ," & str_ireg(op_rd)); -- & " > " & To_HString(op);
            END IF;
 
          WHEN "101" =>
            -- SparcV9 FBPfcc : Floating Point Conditional Branch with Prediction
            RETURN pad(disas_invalide(op));
            
          WHEN "110" =>
            -- FBfcc : Floating Point Conditional Branch
            RETURN pad(disas_fbfcc(op,pc));
            
          WHEN "111" => -- CBccc : Coprocessor Conditional Branch
            RETURN pad("CBccc   ");
            
          WHEN OTHERS =>
            RETURN pad("xxx");
        
        END CASE;
      WHEN "01" =>               -- CALL
        RETURN pad(disas_call (op,pc));
        
      WHEN "10" =>               -- Arith/Logic/FPU
        RETURN pad(disas_alu  (op,pc));
        
      WHEN "11" =>               -- Load/Store
        RETURN pad(disas_lsu  (op,pc));
        
      WHEN OTHERS =>
        RETURN pad("xxx");
        
    END CASE;
    END IF;
    --pragma synthesis_on
  END FUNCTION disassemble;
  --------------------------------------
  PROCEDURE copie (
    SIGNAL   o : OUT string(1 TO 50);
    CONSTANT i : IN  string) IS
  BEGIN
    --pragma synthesis_off
    o<=(OTHERS => ' ');
    o(1 TO i'high)<=i;
    --pragma synthesis_on
  END PROCEDURE copie;

  --############################################################################
  -- Assembleur
  TYPE type_genre IS (
    BRANCH,SETHI,CALL,NOP,ALU,FPU2,FPU3,FPUC,
    WRSPR,RDSPR,LOAD,LOAD_ASI,LOAD_FPU,STORE,STORE_ASI,STORE_FPU,RETT,EQU);
  
  TYPE type_as IS RECORD
    mnemo : string(1 TO 8);
    op    : unsigned(31 downto 0);
    genre : type_genre;
  END RECORD;
  
  TYPE arr_as IS ARRAY (natural RANGE <>) OF type_as;
  
  CONSTANT AS_LISTE : arr_as(1 TO 217) :=(
    ("BN      ", "0000000010----------------------", BRANCH),
    ("BE      ", "0000001010----------------------", BRANCH), -- =BZ
    ("BLE     ", "0000010010----------------------", BRANCH),
    ("BL      ", "0000011010----------------------", BRANCH),
    ("BLEU    ", "0000100010----------------------", BRANCH),
    ("BCS     ", "0000101010----------------------", BRANCH), -- =BLU
    ("BNEG    ", "0000110010----------------------", BRANCH),
    ("BVS     ", "0000111010----------------------", BRANCH),
    ("BA      ", "0001000010----------------------", BRANCH),
    ("BNE     ", "0001001010----------------------", BRANCH), -- =BNZ
    ("BG      ", "0001010010----------------------", BRANCH),
    ("BGE     ", "0001011010----------------------", BRANCH),
    ("BGU     ", "0001100010----------------------", BRANCH),
    ("BCC     ", "0001101010----------------------", BRANCH), -- =BGEU
    ("BPOS    ", "0001110010----------------------", BRANCH),
    ("BVC     ", "0001111010----------------------", BRANCH),
    ("BN,A    ", "0010000010----------------------", BRANCH),
    ("BE,A    ", "0010001010----------------------", BRANCH), -- =BZ,A
    ("BLE,A   ", "0010010010----------------------", BRANCH),
    ("BL,A    ", "0010011010----------------------", BRANCH),
    ("BLEU,A  ", "0010100010----------------------", BRANCH),
    ("BCS,A   ", "0010101010----------------------", BRANCH), -- =BLU,A
    ("BNEG,A  ", "0010110010----------------------", BRANCH),
    ("BVS,A   ", "0010111010----------------------", BRANCH),
    ("BA,A    ", "0011000010----------------------", BRANCH),
    ("BNE,A   ", "0011001010----------------------", BRANCH), -- =BNZ,A
    ("BG,A    ", "0011010010----------------------", BRANCH),
    ("BGE,A   ", "0011011010----------------------", BRANCH),
    ("BGU,A   ", "0011100010----------------------", BRANCH),
    ("BCC,A   ", "0011101010----------------------", BRANCH), -- =BGEU,A
    ("BPOS,A  ", "0011110010----------------------", BRANCH),
    ("BVC,A   ", "0011111010----------------------", BRANCH),
    
    ("SETHI   ", "00-----100----------------------", SETHI),

    ("FBN     ", "0000000110----------------------", BRANCH),
    ("FBNE    ", "0000001110----------------------", BRANCH),
    ("FBLG    ", "0000010110----------------------", BRANCH),
    ("FBUL    ", "0000011110----------------------", BRANCH),
    ("FBL     ", "0000100110----------------------", BRANCH),
    ("FBUG    ", "0000101110----------------------", BRANCH),
    ("FBG     ", "0000110110----------------------", BRANCH),
    ("FBU     ", "0000111110----------------------", BRANCH),
    ("FBA     ", "0001000110----------------------", BRANCH),
    ("FBE     ", "0001001110----------------------", BRANCH),
    ("FBUE    ", "0001010110----------------------", BRANCH),
    ("FBGE    ", "0001011110----------------------", BRANCH),
    ("FBUGE   ", "0001100110----------------------", BRANCH),
    ("FBLE    ", "0001101110----------------------", BRANCH),
    ("FBULE   ", "0001110110----------------------", BRANCH),
    ("FBO     ", "0001111110----------------------", BRANCH),
    ("FBN,A   ", "0010000110----------------------", BRANCH),
    ("FBBE,A  ", "0010001110----------------------", BRANCH),
    ("FBLG,A  ", "0010010110----------------------", BRANCH),
    ("FBUL,A  ", "0010011110----------------------", BRANCH),
    ("FBL,A   ", "0010100110----------------------", BRANCH),
    ("FBUG,A  ", "0010101110----------------------", BRANCH),
    ("FBG,A   ", "0010110110----------------------", BRANCH),
    ("FBU,A   ", "0010111110----------------------", BRANCH),
    ("FBA,A   ", "0011000110----------------------", BRANCH),
    ("FBE,A   ", "0011001110----------------------", BRANCH),
    ("FBUE,A  ", "0011010110----------------------", BRANCH),
    ("FBGE,A  ", "0011011110----------------------", BRANCH),
    ("FBUGE,A ", "0011100110----------------------", BRANCH),
    ("FBLE,A  ", "0011101110----------------------", BRANCH),
    ("FBULE,A ", "0011110110----------------------", BRANCH),
    ("FBO,A   ", "0011111110----------------------", BRANCH),
    
    ("CALL    ", "01------------------------------", CALL),

    ("ADD     ", "10-----000000-------------------", ALU),
    ("AND     ", "10-----000001-------------------", ALU),
    ("OR      ", "10-----000010-------------------", ALU),
    ("XOR     ", "10-----000011-------------------", ALU),
    ("SUB     ", "10-----000100-------------------", ALU),
    ("ANDN    ", "10-----000101-------------------", ALU),
    ("ORN     ", "10-----000110-------------------", ALU),
    ("XNOR    ", "10-----000111-------------------", ALU),
    ("ADDX    ", "10-----001000-------------------", ALU),
--    ("MULX     ", "10-----001001-------------------", ALU), -- SparcV9
    ("UMUL    ", "10-----001010-------------------", ALU),
    ("SMUL    ", "10-----001011-------------------", ALU),
    ("SUBX    ", "10-----001100-------------------", ALU),
--    ("UDIVX    ", "10-----001101-------------------", ALU), -- SparcV9
    ("UDIV    ", "10-----001110-------------------", ALU),
    ("SDIV    ", "10-----001111-------------------", ALU),
    ("ADDcc   ", "10-----010000-------------------", ALU),
    ("ANDcc   ", "10-----010001-------------------", ALU),
    ("ORcc    ", "10-----010010-------------------", ALU),
    ("XORcc   ", "10-----010011-------------------", ALU),
    ("SUBcc   ", "10-----010100-------------------", ALU),
    ("ANDNcc  ", "10-----010101-------------------", ALU),
    ("ORNcc   ", "10-----010110-------------------", ALU),
    ("XNORcc  ", "10-----010111-------------------", ALU),
    ("ADDXcc  ", "10-----011000-------------------", ALU),
    ("INVALID ", "10-----011001-------------------", ALU),
    ("UMULcc  ", "10-----011010-------------------", ALU),
    ("SMULcc  ", "10-----011011-------------------", ALU),
    ("SUBXcc  ", "10-----011100-------------------", ALU),
    ("DIVScc  ", "10-----011101-------------------", ALU), -- SparcV8e
    ("UDIVcc  ", "10-----011110-------------------", ALU),
    ("SDIVcc  ", "10-----011111-------------------", ALU),
    ("TADDcc  ", "10-----100000-------------------", ALU),
    ("TSUBcc  ", "10-----100001-------------------", ALU),
    ("TADDccTV", "10-----100010-------------------", ALU),
    ("TSUBccTV", "10-----100011-------------------", ALU),
    ("MULScc  ", "10-----100100-------------------", ALU),
    ("SLL     ", "10-----100101-------------------", ALU),
    ("SRL     ", "10-----100110-------------------", ALU),
    ("SRA     ", "10-----100111-------------------", ALU),
    ("RDY     ", "10-----101000-------------------", RDSPR),
    ("RDPSR   ", "10-----101001-------------------", RDSPR),
    ("RDWIM   ", "10-----101010-------------------", RDSPR),
    ("RDTBR   ", "10-----101011-------------------", RDSPR),
--    ("MOVcc   ", "10-----101100-------------------", ALU),
--    ("SDIVX   ", "10-----101101-------------------", ALU),
--    ("POPC    ", "10-----101110-------------------", ALU),
--    ("MOVr    ", "10-----101111-------------------", ALU),
    ("WRY     ", "10-----110000-------------------", WRSPR),
    ("WRPSR   ", "10-----110001-------------------", WRSPR),
    ("WRWIM   ", "10-----110010-------------------", WRSPR),
    ("WRTBR   ", "10-----110011-------------------", WRSPR),
--    ("FPop1   ", "10-----110100-------------------", ALU),
    ("FiTOs   ", "10-----110100-----011000100-----", FPU2),
    ("FiTOd   ", "10-----110100-----011001000-----", FPU2),
    ("FiTOq   ", "10-----110100-----011001100-----", FPU2),
    ("FsTOi   ", "10-----110100-----011010001-----", FPU2),
    ("FdTOi   ", "10-----110100-----011010010-----", FPU2),
    ("FqTOi   ", "10-----110100-----011010011-----", FPU2),
    ("FsTOd   ", "10-----110100-----011001001-----", FPU2),
    ("FsTOq   ", "10-----110100-----011001101-----", FPU2),
    ("FdTOs   ", "10-----110100-----011000110-----", FPU2),
    ("FdTOq   ", "10-----110100-----011001110-----", FPU2),
    ("FqTOs   ", "10-----110100-----011000111-----", FPU2),
    ("FqTOd   ", "10-----110100-----011001011-----", FPU2),
    ("FMOVs   ", "10-----110100-----000000001-----", FPU2),
    ("FNEGs   ", "10-----110100-----000000101-----", FPU2),
    ("FABSs   ", "10-----110100-----000001001-----", FPU2),
    ("FSQRTs  ", "10-----110100-----000101001-----", FPU2),
    ("FSQRTd  ", "10-----110100-----000101010-----", FPU2),
    ("FSQRTq  ", "10-----110100-----000101011-----", FPU2),
    ("FADDs   ", "10-----110100-----001000001-----", FPU3),
    ("FADDd   ", "10-----110100-----001000010-----", FPU3),
    ("FADDq   ", "10-----110100-----001000011-----", FPU3),
    ("FSUBs   ", "10-----110100-----001000101-----", FPU3),
    ("FSUBd   ", "10-----110100-----001000110-----", FPU3),
    ("FSUBq   ", "10-----110100-----001000111-----", FPU3),
    ("FMULs   ", "10-----110100-----001001001-----", FPU3),
    ("FMULd   ", "10-----110100-----001001010-----", FPU3),
    ("FMULq   ", "10-----110100-----001001011-----", FPU3),
    ("FsMULd  ", "10-----110100-----001101001-----", FPU3),
    ("FdMULq  ", "10-----110100-----001101110-----", FPU3),
    ("FDIVs   ", "10-----110100-----001001101-----", FPU3),
    ("FDIVd   ", "10-----110100-----001001110-----", FPU3),
    ("FDIVq   ", "10-----110100-----001001111-----", FPU3),
--    ("FPop2   ", "10-----110101-------------------", ALU),
    ("FCMPs   ", "10-----110101-----001010001-----", FPUC),
    ("FCMPd   ", "10-----110101-----001010010-----", FPUC),
    ("FCMPq   ", "10-----110101-----001010011-----", FPUC),
    ("FCMPEs  ", "10-----110101-----001010101-----", FPUC),
    ("FCMPEd  ", "10-----110101-----001010110-----", FPUC),
    ("FCMPEq  ", "10-----110101-----001010111-----", FPUC),
--    ("CPop1    ", "10-----110110-------------------", ALU),
--    ("CPop2    ", "10-----110111-------------------", ALU),
    ("JMPL    ", "10-----111000-------------------", LOAD), -- JMPL address,Rd
    ("RETT    ", "10-----111001-------------------", RETT), -- RETT address
--    ("Ticc    ", "10-----111010-------------------", RETT),
    ("TN      ", "10-0000111010-------------------", RETT),
    ("TE      ", "10-0001111010-------------------", RETT), -- =TZ
    ("TLE     ", "10-0010111010-------------------", RETT),
    ("TL      ", "10-0011111010-------------------", RETT),
    ("TLEU    ", "10-0100111010-------------------", RETT),
    ("TCS     ", "10-0101111010-------------------", RETT), -- =TLU
    ("TNEG    ", "10-0110111010-------------------", RETT),
    ("TVS     ", "10-0111111010-------------------", RETT),
    ("TA      ", "10-1000111010-------------------", RETT),
    ("TNE     ", "10-1001111010-------------------", RETT), -- =TNZ
    ("TG      ", "10-1010111010-------------------", RETT),
    ("TGE     ", "10-1011111010-------------------", RETT),
    ("TGU     ", "10-1100111010-------------------", RETT),
    ("TCC     ", "10-1101111010-------------------", RETT), -- =TGEU
    ("TPOS    ", "10-1110111010-------------------", RETT),
    ("TVC     ", "10-1111111010-------------------", RETT),
    
    ("IFLUSH  ", "10-----111011-------------------", RETT), -- IFLUSH address
    ("SAVE    ", "10-----111100-------------------", ALU),
    ("RESTORE ", "10-----111101-------------------", ALU),
--    ("        ", "10-----111110-------------------", ALU),
--    ("        ", "10-----111111-------------------", ALU),

    ("LD      ", "11-----000000-------------------", LOAD),
    ("LDUB    ", "11-----000001-------------------", LOAD),
    ("LDUH    ", "11-----000010-------------------", LOAD),
    ("LDD     ", "11-----000011-------------------", LOAD),
    ("ST      ", "11-----000100-------------------", STORE),
    ("STB     ", "11-----000101-------------------", STORE),
    ("STH     ", "11-----000110-------------------", STORE),
    ("STD     ", "11-----000111-------------------", STORE),
--    ("INVALID ", "11-----001000-------------------", NOP),
    ("LDSB    ", "11-----001001-------------------", LOAD),
    ("LDSH    ", "11-----001010-------------------", LOAD),
--    ("INVALID ", "11-----001011-------------------", NOP),
--    ("INVALID ", "11-----001100-------------------", NOP),
    ("LDSTUB  ", "11-----001101-------------------", LOAD),
--    ("INVALID ", "11-----001110-------------------", NOP),
    ("SWAP    ", "11-----001111-------------------", LOAD),
    ("LDA     ", "11-----010000-------------------", LOAD_ASI),
    ("LDUBA   ", "11-----010001-------------------", LOAD_ASI),
    ("LDUHA   ", "11-----010010-------------------", LOAD_ASI),
    ("LDDA    ", "11-----010011-------------------", LOAD_ASI),
    ("STA     ", "11-----010100-------------------", STORE_ASI),
    ("STBA    ", "11-----010101-------------------", STORE_ASI),
    ("STHA    ", "11-----010110-------------------", STORE_ASI),
    ("STDA    ", "11-----010111-------------------", STORE_ASI),
--    ("INVALID ", "11-----011000-------------------", NOP),
    ("LDSBA   ", "11-----011001-------------------", LOAD_ASI),
    ("LDSHA   ", "11-----011010-------------------", LOAD_ASI),
--    ("INVALID ", "11-----011011-------------------", NOP),
--    ("INVALID ", "11-----011100-------------------", NOP),
    ("LDSTUBA ", "11-----011101-------------------", LOAD_ASI),
--    ("INVALID ", "11-----011110-------------------", NOP),
    ("SWAPA   ", "11-----011111-------------------", LOAD_ASI),
    ("LDF     ", "11-----100000-------------------", LOAD_FPU),
    ("LDFSR   ", "11-----100001-------------------", RETT),
--    ("INVALID ", "11-----100010-------------------", NOP),
    ("LDDF    ", "11-----100011-------------------", LOAD_FPU),
    ("STF     ", "11-----100100-------------------", STORE_FPU),
    ("STFSR   ", "11-----100101-------------------", RETT), --STFSR [address]
    ("STDFQ   ", "11-----100110-------------------", RETT), --STDFQ [address]
    ("STDF    ", "11-----100111-------------------", STORE_FPU),
--    ("INVALID ", "11-----101000-------------------", NOP),
--    ("INVALID ", "11-----101001-------------------", NOP),
--    ("INVALID ", "11-----101010-------------------", NOP),
--    ("INVALID ", "11-----101011-------------------", NOP),
--    ("INVALID ", "11-----101100-------------------", NOP),
--    ("INVALID ", "11-----101101-------------------", NOP),
--    ("INVALID ", "11-----101110-------------------", NOP),
--    ("INVALID ", "11-----101111-------------------", NOP),
    ("LDC     ", "11-----110000-------------------", LOAD),
    ("LDCSR   ", "11-----110001-------------------", LOAD),
--    ("INVALID ", "11-----110010-------------------", NOP),
    ("LDDC    ", "11-----110011-------------------", LOAD),
    ("STC     ", "11-----110100-------------------", LOAD),
    ("STCSR   ", "11-----110101-------------------", LOAD),
    ("STDCQ   ", "11-----110110-------------------", LOAD),
    ("STDC    ", "11-----110111-------------------", LOAD),
--    ("INVALID ", "11-----111000-------------------", NOP),
--    ("INVALID ", "11-----111001-------------------", NOP),
--    ("INVALID ", "11-----111010-------------------", NOP),
--    ("INVALID ", "11-----111011-------------------", NOP),
    ("CASA    ", "11-----111100-------------------", LOAD_ASI),
--    ("INVALID ", "11-----111101-------------------", NOP),
--    ("INVALID ", "11-----111110-------------------", NOP),
--    ("INVALID ", "11-----111111-------------------", NOP),

    ("UNIMP   ", "00-----000----------------------", NOP),  --UNIMP
    ("NOP     ", "00000001000000000000000000000000", NOP),  --NOP = SETHI 0,g0
    ("RET     ", "10000001110001111110000000001000", NOP),  --RET  = JMPL %i7+8,%g0
    ("RETL    ", "10000001110000111110000000001000", NOP),  --RETL = JMPL %o7+8,%g0
    ("JMP     ", "1000000111000-------------------", RETT),  --JMP address = JMPL address,%g0
    ("CALL    ", "1001111111000-------------------", RETT),  --CALL address = JMPL address,%o7
    
    ("EQU     ", "--------------------------------", EQU )
    );
  
  TYPE type_nom_reg IS RECORD
    nom : string(1 TO 3);
    v   : natural;
  END RECORD;
  TYPE arr_nom_reg IS ARRAY (natural RANGE <>) OF type_nom_reg;

  CONSTANT AS_IREG : arr_nom_reg(1 TO 64) := (
    ("R0 ",0 ),("G0 ",0 ),    ("R1 ",1 ),("G1 ",1 ),
    ("R2 ",2 ),("G2 ",2 ),    ("R3 ",3 ),("G3 ",3 ),
    ("R4 ",4 ),("G4 ",4 ),    ("R5 ",5 ),("G5 ",5 ),
    ("R6 ",6 ),("G6 ",6 ),    ("R7 ",7 ),("G7 ",7 ),
    ("R8 ",8 ),("O0 ",8 ),    ("R9 ",9 ),("O1 ",9 ),
    ("R10",10),("O2 ",10),    ("R11",11),("O3 ",11),
    ("R12",12),("O4 ",12),    ("R13",13),("O5 ",13),
    ("R14",14),("O6 ",14),    ("R15",15),("O7 ",15),
    ("R16",16),("L0 ",16),    ("R17",17),("L1 ",17),
    ("R18",18),("L2 ",18),    ("R19",19),("L3 ",19),
    ("R20",20),("L4 ",20),    ("R21",21),("L5 ",21),
    ("R22",22),("L6 ",22),    ("R23",23),("L7 ",23),
    ("R24",24),("I0 ",24),    ("R25",25),("I1 ",25),
    ("R26",26),("I2 ",26),    ("R27",27),("I3 ",27),
    ("R28",28),("I4 ",28),    ("R29",29),("I5 ",29),
    ("R30",30),("I6 ",30),    ("R31",31),("I7 ",31));
    
  CONSTANT AS_FREG : arr_nom_reg(1 TO 32) := (
    ("F0 ",0 ),    ("F1 ",1 ),    ("F2 ",2 ),    ("F3 ",3 ),
    ("F4 ",4 ),    ("F5 ",5 ),    ("F6 ",6 ),    ("F7 ",7 ),
    ("F8 ",8 ),    ("F9 ",9 ),    ("F10",10),    ("F11",11),
    ("F12",12),    ("F13",13),    ("F14",14),    ("F15",15),
    ("F16",16),    ("F17",17),    ("F18",18),    ("F19",19),
    ("F20",20),    ("F21",21),    ("F22",22),    ("F23",23),
    ("F24",24),    ("F25",25),    ("F26",26),    ("F27",27),
    ("F28",28),    ("F29",29),    ("F30",30),    ("F31",31));
    
  FUNCTION isdigit (c : character; b : natural) RETURN boolean IS
    VARIABLE r : boolean;
  BEGIN
    r:=false;
    IF b=10 THEN
      CASE c IS
        WHEN '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'  =>
          r:=true;
        WHEN OTHERS =>
          r:=false;
      END CASE;
    ELSIF b=16 THEN
      CASE c IS
        WHEN '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' |
             '8' | '9' | 'a' | 'A' | 'b' | 'B' | 'c' | 'C' |
             'd' | 'D' | 'e' | 'E' | 'f' | 'F' =>
          r:=true;
        WHEN OTHERS =>
          r:=false;
      END CASE;
    END IF;
    RETURN r;
  END FUNCTION isdigit;
  
  --------------------------------------
  PROCEDURE parse_int (sui    : OUT natural;
                       trouve : OUT boolean;
                       v      : OUT integer;
                       s      : IN  string) IS
    VARIABLE i,j : natural;
    VARIABLE base : natural := 10;
    VARIABLE signe : integer :=1;
    VARIABLE high : boolean := false;
    VARIABLE simm13 : boolean := false;
    VARIABLE uimm12 : boolean := false;
  BEGIN
    i:=s'low;
    trouve:=false;
    WHILE s(i)=' ' OR s(i)=',' OR s(i)='[' OR s(i)=']' LOOP
      i:=i+1;
    END LOOP;
    IF s(i)='+' THEN
      signe:=1;
      i:=i+1;
    ELSIF s(i)='-' THEN
      signe:=-1;
      i:=i+1;
    END IF;
    WHILE s(i)=' ' LOOP
      i:=i+1;
    END LOOP;
    IF s(i)='h' THEN
      high:=true;
      i:=i+1;
    END IF;
    IF s(i)='s' THEN
      simm13:=true;
      i:=i+1;
    END IF;
    IF s(i)='u' THEN
      uimm12:=true;
      i:=i+1;
    END IF;
    
    IF s(i)='x' THEN
      base:=16;
      i:=i+1;
    END IF;
    j:=i;
    WHILE isdigit(s(i),base) LOOP
      i:=i+1;
      EXIT WHEN i>s'high;
    END LOOP;
    sui:=i;
    IF i>j THEN
      trouve:=true;
      -- Plein de magouilles pour passer dans des entiers signés sur 32bits
      IF high AND base=16 AND j<i-2 THEN
        v:= signe * to_natural(s(j TO i-2),base)/(1024/16);
      ELSIF uimm12 AND base=16 AND j<i-5 THEN
        v:= signe * (to_natural(s(j+1 TO i-1),base) MOD 4096);
      ELSIF uimm12 AND base=16 THEN
        v:= signe * (to_natural(s(j TO i-1),base) MOD 4096);
      ELSIF simm13 AND base=16 AND j<i-5 THEN
        v:= signe * (to_natural(s(j+1 TO i-1),base) MOD 8192);
      ELSIF simm13 AND base=16 THEN
        v:= signe * (to_natural(s(j TO i-1),base) MOD 8192);
      ELSIF NOT high AND NOT uimm12 AND NOT simm13 THEN
        v:= signe * to_natural(s(j TO i-1),base);
      ELSE
        REPORT "Problème :" & s(j TO i-1) SEVERITY failure;
      END IF;
    ELSE
      trouve:=false;
      v:=0;
    END IF;
  END PROCEDURE parse_int;

  --------------------------------------
  PROCEDURE parse_ireg (sui   : OUT natural;
                       trouve : OUT boolean;
                       v      : OUT integer;
                       s      : IN  string) IS
    VARIABLE i,j : natural;
    VARIABLE signe : integer;
    VARIABLE ts : string(1 TO 3) :="   ";
  BEGIN
    i:=s'low;
    trouve:=false;
    WHILE s(i)=' ' OR s(i)=',' OR s(i)='[' OR s(i)=']' OR s(i)='+' LOOP
      i:=i+1;
    END LOOP;
    j:=i;
    WHILE i/=s'high+1 LOOP
      IF s(i)=' ' OR s(i)=',' OR s(i)='[' OR s(i)=']' OR s(i)='+' THEN
        EXIT;
      END IF;
      i:=i+1;
    END LOOP;
    i:=i-1;
    sui:=i+1;
    IF i=j+1 THEN
      ts:=s(j) & s(j+1) & ' ';
    ELSIF i=j+2 THEN
      ts:=s(j) & s(j+1) & s(j+2);
    ELSE
      RETURN;
    END IF;
    FOR i IN AS_IREG'range LOOP
      IF ts=AS_IREG(i).nom THEN
        trouve:=true;
        v:=AS_IREG(i).v;
        RETURN;
      END IF;
    END LOOP;
  END PROCEDURE parse_ireg;
  
  --------------------------------------
  PROCEDURE parse_freg (sui   : OUT natural;
                       trouve : OUT boolean;
                       v      : OUT integer;
                       s      : IN  string) IS
    VARIABLE i,j : natural;
    VARIABLE signe : integer;
    VARIABLE ts : string(1 TO 3) :="   ";
  BEGIN
    i:=s'low;
    trouve:=false;
    WHILE s(i)=' ' OR s(i)=',' OR s(i)='[' OR s(i)=']' LOOP
      i:=i+1;
    END LOOP;
    j:=i;
    WHILE i/=s'high+1 LOOP
      IF s(i)=' ' OR s(i)=',' OR s(i)='[' OR s(i)=']' THEN
        EXIT;
      END IF;
      i:=i+1;
    END LOOP;
    i:=i-1;
    sui:=i+1;
    IF i=j+1 THEN
      ts:=s(j) & s(j+1) & ' ';
    ELSIF i=j+2 THEN
      ts:=s(j) & s(j+1) & s(J+2);
    ELSE
      RETURN;
    END IF;
    FOR i IN AS_FREG'range LOOP
      IF ts=AS_FREG(i).nom THEN
        trouve:=true;
        v:=AS_FREG(i).v;
        RETURN;
      END IF;
    END LOOP;
  END PROCEDURE parse_freg;
  
  --------------------------------------
  FUNCTION w (
    CONSTANT s : unsigned)
    RETURN unsigned IS
    VARIABLE r : unsigned(s'range):=s;
  BEGIN
    FOR i IN s'range LOOP
      IF s(i)='-' THEN
        r(i):='0';
      END IF;
    END LOOP;
    RETURN r;
  END FUNCTION w;

  --------------------------------------
  -- Assemblage d'une instruction
  FUNCTION assemble (
    CONSTANT code : string)
    RETURN unsigned IS
    VARIABLE i,j,jj,k : natural;
    VARIABLE trouve : boolean := false;
    VARIABLE tr : boolean;
    VARIABLE mnemo : string(1 TO 8):="        ";
    VARIABLE ti : integer;
    VARIABLE rs1,rs2,rd : integer;
  BEGIN
    i:=1;
    j:=1;
    -- Extraction mnémonique
    WHILE code(I)=' ' LOOP
      I:=I+1;
    END LOOP;
    WHILE I/=code'length+1 AND code(I)/=' ' LOOP
      mnemo(J):=code(I);
      I:=I+1;
      J:=J+1;
    END LOOP;
    -- Recherche mnémonique
    FOR kk IN AS_LISTE'range LOOP
      IF mnemo= AS_LISTE(kk).mnemo THEN
        trouve:=true;
        k:=kk;
        EXIT;
      END IF;
    END LOOP;
    ASSERT trouve REPORT "J'ai pas compris :" & code SEVERITY failure;
  
    -- Tri par type d'instruction
    CASE AS_LISTE(k).genre IS
      WHEN BRANCH =>
        -- Bicc imm22 ou FBcc imm22
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR uext(unsigned(to_signed(ti,22)),32);
        
      WHEN SETHI =>
        -- SETHI imm22, Reg
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "---" & unsigned(to_signed(ti,22)));
        
      WHEN CALL =>
        -- CALL disp30
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR uext(unsigned(to_signed(ti,30)),32);
        
      WHEN NOP =>
        -- NOP
        RETURN w(AS_LISTE(k).op) OR x"00000000";

      WHEN ALU =>
        -- ADD RegS1 , RegS2, RegD     ADD RegS1 , Imm , RegD
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          j:=jj;
          parse_ireg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          j:=jj;
          parse_ireg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN FPU2 =>
        -- FABSs FRegS2, FRegD
        parse_freg(jj,tr,rs2,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_freg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "------" &
          "00000" & "---------" &  to_unsigned(rs2,5));
        
      WHEN FPU3 =>
        -- FADDd FRegS1, FRegS2, FRegD
        parse_freg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_freg(jj,tr,rs2,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_freg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "------" &
          to_unsigned(rs1,5) & "---------" &  to_unsigned(rs2,5));
        
      WHEN FPUC =>
        -- FCMPd FRegS1, FRegS2
        parse_freg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_freg(jj,tr,rs2,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & "00000" & "------" &
          to_unsigned(rs1,5) & "---------" &  to_unsigned(rs2,5));

      WHEN WRSPR =>
        -- WRWIM RegS1, RegS2   ou     WRWIM RegS1, Imm
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          RETURN w(AS_LISTE(k).op) OR
            w("--" & "00000" & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & "00000" & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN RDSPR =>
        -- RDWIM RegD
        parse_ireg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "------" &
          "0000000000000000000");
      WHEN LOAD =>
        -- LD [RegS1 + RegS2],RegD  ou    LD [RegS1 + Imm],RegD
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          j:=jj;
          parse_ireg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          j:=jj;
          parse_ireg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN LOAD_ASI =>
        -- LD [RegS1 + RegS2]ASI,RegD
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "------" &
          to_unsigned(rs1,5) & '0' & to_unsigned(ti,8) &  to_unsigned(rs2,5));
        
      WHEN LOAD_FPU =>
        -- LDF [RegS1 + RegS2],FRegD  ou    LDF [RegS1 + Imm],FRegD
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          j:=jj;
          parse_freg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          j:=jj;
          parse_freg(jj,tr,rd,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN STORE =>
        -- ST RegD, [RegS1 + RegS2]   ou   ST RegD, [RegS1 + Imm]
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN STORE_ASI =>
        -- ST RegD, [RegS1 + RegS2]ASI
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN w(AS_LISTE(k).op) OR
          w("--" & to_unsigned(rd,5) & "------" &
          to_unsigned(rs1,5) & '0' & to_unsigned(ti,8) &  to_unsigned(rs2,5));
        
      WHEN STORE_FPU =>
        -- STF FRegD, [RegS1 + RegS2]    ou   STF FRegD, [RegS1 + Imm]
        -- <AFAIRE> R0 facultatif
        parse_freg(jj,tr,rd,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & to_unsigned(rd,5) & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN RETT =>
        -- RETT RegS1 + RegS2 ou RETT RegS1 + Imm
        -- <AFAIRE> R0 facultatif
        parse_ireg(jj,tr,rs1,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        j:=jj;
        parse_ireg(jj,tr,rs2,code(j TO code'high));
        IF tr THEN
          RETURN w(AS_LISTE(k).op) OR
            w("--" & "00000" & "------" &
            to_unsigned(rs1,5) & "000000000" &  to_unsigned(rs2,5));
        ELSE
          parse_int(jj,tr,ti,code(j TO code'high));
          ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
          RETURN w(AS_LISTE(k).op) OR
            w("--" & "00000" & "------" &
            to_unsigned(rs1,5) & '1' & unsigned(to_signed(ti,13)));
        END IF;
        
      WHEN EQU =>
        -- EQU Imm32
        parse_int(jj,tr,ti,code(j TO code'high));
        ASSERT tr REPORT "J'ai pas compris :" & code SEVERITY failure;
        RETURN unsigned(to_signed(ti,32));
        
    END CASE;
  END FUNCTION assemble;

  --############################################################################
  -- Assemblage : Calcul valeur immédiate pour SETHI
  FUNCTION imm22 (
    CONSTANT val : uv32)
    RETURN string IS
  BEGIN
    RETURN "x" & To_HString("00" & val(31 DOWNTO 10));
  END FUNCTION imm22;
  
  --------------------------------------
  -- Assemblage : Calcul valeur immédiate pour opérations ALU
  FUNCTION simm13 (
    CONSTANT val : uv32)
    RETURN string IS
  BEGIN
    RETURN "x" & To_HString("000" & val(12 DOWNTO 0));
  END FUNCTION simm13;
  
  --------------------------------------
  -- Assemblage : Calcul valeur immédiate pour opérations ALU
  FUNCTION imm12 (
    CONSTANT val : uv32)
    RETURN string IS
  BEGIN
    RETURN "x" & To_HString(val(11 DOWNTO 0));
  END FUNCTION imm12;

  --------------------------------------
  -- Assemblage : Calcul sauts relatifs pour branchements
  FUNCTION branch_calc (
    CONSTANT src  : natural;
    CONSTANT dest : natural)
    RETURN string IS
  BEGIN
    RETURN integer'image((dest-src)/4);
  END FUNCTION branch_calc;
  
  --############################################################################
  FUNCTION trap_decode (
    CONSTANT t : type_trap)
    RETURN string IS
  BEGIN
  --pragma synthesis_off
    IF t.t='0' THEN
  --pragma synthesis_on
      RETURN "";
  --pragma synthesis_off
    ELSE
      CASE t.tt IS
        WHEN x"00" => RETURN "TT_RESET";
        WHEN x"2B" => RETURN "TT_DATA_STORE_ERROR";
        WHEN x"3C" => RETURN "TT_INSTRUCTION_ACCESS_MMU_MISS";
        WHEN x"21" => RETURN "TT_INSTRUCTION_ACCESS_ERROR";
        WHEN x"20" => RETURN "TT_R_REGISTER_ACCESS_ERROR";
        WHEN x"01" => RETURN "TT_INSTRUCTION_ACCESS_EXCEPTION";
        WHEN x"03" => RETURN "TT_PRIVILEGED_INSTRUCTION";
        WHEN x"02" => RETURN "TT_ILLEGAL_INSTRUCTION";
        WHEN x"04" => RETURN "TT_FP_DISABLED";
        WHEN x"24" => RETURN "TT_CP_DISABLED";
        WHEN x"25" => RETURN "TT_UNIMPLEMENTED_FLUSH";
        WHEN x"0B" => RETURN "TT_WATCHPOINT_DETECTED";
        WHEN x"05" => RETURN "TT_WINDOW_OVERFLOW";
        WHEN x"06" => RETURN "TT_WINDOW_UNDERFLOW";
        WHEN x"07" => RETURN "TT_MEM_ADDRESS_NOT_ALIGNED";
        WHEN x"08" => RETURN "TT_FP_EXCEPTION";
        WHEN x"28" => RETURN "TT_CP_EXCEPTION";
        WHEN x"29" => RETURN "TT_DATA_ACCESS_ERROR";
        WHEN x"2C" => RETURN "TT_DATA_ACCESS_MMU_MISS";
        WHEN x"09" => RETURN "TT_DATA_ACCESS_EXCEPTION";
        WHEN x"0A" => RETURN "TT_TAG_OVERFLOW";
        WHEN x"2A" => RETURN "TT_DIVISION_BY_ZERO";  
        WHEN x"80" => RETURN "TT_TRAP_INSTRUCTION";  
        WHEN x"1F" => RETURN "TT_INTERRUPT_LEVEL_15";
        WHEN x"1E" => RETURN "TT_INTERRUPT_LEVEL_14";
        WHEN x"1D" => RETURN "TT_INTERRUPT_LEVEL_13";
        WHEN x"1C" => RETURN "TT_INTERRUPT_LEVEL_12";
        WHEN x"1B" => RETURN "TT_INTERRUPT_LEVEL_11";
        WHEN x"1A" => RETURN "TT_INTERRUPT_LEVEL_10";
        WHEN x"19" => RETURN "TT_INTERRUPT_LEVEL_9";
        WHEN x"18" => RETURN "TT_INTERRUPT_LEVEL_8";
        WHEN x"17" => RETURN "TT_INTERRUPT_LEVEL_7";
        WHEN x"16" => RETURN "TT_INTERRUPT_LEVEL_6";
        WHEN x"15" => RETURN "TT_INTERRUPT_LEVEL_5";
        WHEN x"14" => RETURN "TT_INTERRUPT_LEVEL_4";
        WHEN x"13" => RETURN "TT_INTERRUPT_LEVEL_3";
        WHEN x"12" => RETURN "TT_INTERRUPT_LEVEL_2";
        WHEN x"11" => RETURN "TT_INTERRUPT_LEVEL_1";                     
        WHEN OTHERS => RETURN "Trap Inconnu";
      END CASE;
    END IF;
  --pragma synthesis_on
  END FUNCTION trap_decode;
  
END PACKAGE BODY disas_pack;

