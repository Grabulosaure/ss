/* Debugger.
   Désassemblage

   DO 6/2011
*/
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "lib.h"

const char *IREG[32] = {
    "(0) ", "%g1 ", "%g2 ", "%g3 ", "%g4 ", "%g5 ", "%g6 ", "%g7 ",
    "%o0 ", "%o1 ", "%o2 ", "%o3 ", "%o4 ", "%o5 ", "%sp ", "%o7 ",
    "%l0 ", "%l1 ", "%l2 ", "%l3 ", "%l4 ", "%l5 ", "%l6 ", "%l7 ",
    "%i0 ", "%i1 ", "%i2 ", "%i3 ", "%i4 ", "%i5 ", "%fp ", "%i7 "
};

const char *FREG[32] = {
    "%f0 ", "%f1 ", "%f2 ", "%f3 ", "%f4 ", "%f5 ", "%f6 ", "%f7 ",
    "%f8 ", "%f9 ", "%f10", "%f11", "%f12", "%f13", "%f14", "%f15",
    "%f16", "%f17", "%f18", "%f19", "%f20", "%f21", "%f22", "%f23",
    "%f24", "%f25", "%f26", "%f27", "%f28", "%f29", "%f30", "%f31"
};

const char *ICOND[32] = {
    "N    ", "E    ", "LE   ", "L    ", "LEU  ", "CS   ", "NEG  ", "VS   ",
    "A    ", "NE   ", "G    ", "GE   ", "GU   ", "CC   ", "POS  ", "VC   ",
    "N,A  ", "E,A  ", "LE,A ", "L,A  ", "LEU,A", "CS,A ", "NEG,A", "VS,A ",
    "A,A  ", "NE,A ", "G,A  ", "GE,A ", "GU,A ", "CC,A ", "POS,A", "VC,A "
};

const char *FCOND[32] = {
    "N    ", "NE   ", "LG   ", "UL   ", "L    ", "UG   ", "G    ", "U    ",
    "A    ", "E    ", "UE   ", "GE   ", "UGE  ", "LE   ", "ULE  ", "O    ",
    "N,A  ", "NE,A ", "LG,A ", "UL,A ", "L,A  ", "UG,A ", "G,A  ", "U,A  ",
    "A,A  ", "E,A  ", "UE,A ", "GE,A ", "UGE,A", "LE,A ", "ULE,A", "O,A  "
};

//--------------------------------------------------------------------

typedef struct {
    uint32_t a;
    char c;
    char *s;
} t_sym;

t_sym *stbl;

int slen = 0;

void razmap()
{
    slen = 0;
    if (stbl) free(stbl);
}

// AFAIRE : QSORT  / BSEARCH
int readmap(const char *mapfile)
{
    char tmp[100];
    char c;
    unsigned a, l,l2;
    FILE *fil;
    unsigned len, i;
    uprintf ("ReadMap %s\n",mapfile);
    
    fil = fopen(mapfile, "r");
    if (!fil)
        return -1;
    l = 0;
    do {
        fgets(tmp, 99, fil);
        l++;
    } while (!feof(fil));
    
    stbl  = realloc(stbl,(slen+l) * sizeof(t_sym));
    
    rewind(fil);
    l2 = slen;
    do {
        fgets(tmp, 99, fil);
        len = strlen(tmp);
        if (len < 2)
            continue;
        for (i = 0; (i < len) && (tmp[i] != ' '); i++);
        sscanf(tmp, "%X", &a);

        for (i = len - 1; (i > 0) && (tmp[i]) && (tmp[i] != ' '); i--);
        tmp[len - 1] = 0;

        stbl[l2].a = a;
        stbl[l2].c = c;
        stbl[l2].s = strdup(&tmp[i + 1]);
        l2++;
    } while (!feof(fil));
    fclose(fil);
    slen=l2;
    uprintf ("SLEN=%i\n",slen);
}

char *symbol(uint32_t a)
{
    unsigned l;
    for (l = 0; l < slen; l++)
        if (stbl[l].a == a)
            return stbl[l].s;
    return "";
}

char symb[100];

char *symboli(uint32_t a)
{
    unsigned l, tr, p;
    uint32_t min, diff;
    tr = 0;

    for (l = 0; l < slen; l++) {
        if ((stbl[l].a <= a) && (((a - stbl[l].a) < diff) || (tr == 0))) {
            tr = 1;
            diff = a - stbl[l].a;
            p = l;
        }
    }

    if (tr == 0)
        return "";
    if (diff == 0)
        strcpy(symb, stbl[p].s);
    else
        sprintf(symb, "%s + %3i", stbl[p].s, diff);
    return symb;
}

int symbolt(char *s,uint32_t *pv)
{
    unsigned l;
    for (l = 0; l < slen; l++) {
        if (!strcmp(s, stbl[l].s)) {
            *pv=stbl[l].a;
            return 0;
        }
    }
    return -1;
}


//  --------------------------------------

#define BIF(x,y,z) ((x>>z)&((1<<(y-z+1))-1))
#define BIK(x,y) BIF(x,y,y)

void rspido(char *s, uint32_t op)
{
    int32_t v;
    uint32_t rs1, rs2;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);

    if (BIK(op, 13)) {
        //  sprintf(s,"%s + x%X",IREG[rs1],v); 
        if (v != 0)
            sprintf(s, "%s + x%X", IREG[rs1], v);
        else
            strcpy(s, IREG[rs1]);
    } else {
        //sprintf (s,"%s + %s",IREG[rs1],IREG[rs2]);
        if (rs1 != 0 && rs2 != 0)
            sprintf(s, "%s + %s", IREG[rs1], IREG[rs2]);
        else if (rs1 != 0)
            strcpy(s, IREG[rs1]);
        else if (rs2 != 0)
            strcpy(s, IREG[rs2]);
        else
            strcpy(s, "0");
    }
}

void disas_arith(char *s, uint32_t op, char *co)
{
    int32_t v;
    uint32_t rs1, rs2, rd;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);

    if (BIK(op, 13)) {
        sprintf(s, "%s%s, 0x%+X,%s", co, IREG[rs1], v, IREG[rd]);
    } else {
        sprintf(s, "%s%s,%s,%s", co, IREG[rs1], IREG[rs2], IREG[rd]);
    }
}

void disas_comp(char *s, uint32_t op, char *co)
{
    int32_t v;
    uint32_t rs1, rs2;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);

    if (BIK(op, 13)) {
        sprintf(s, "%s%s, %+d", co, IREG[rs1], v);
    } else {
        sprintf(s, "%s%s,%s", co, IREG[rs1], IREG[rs2]);
    }
}

void disas_mov(char *s, uint32_t op, char *co)
{
    int32_t v;
    uint32_t rs2, rd;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);

    if (BIK(op, 13)) {
        sprintf(s, "%s%+d,%s", co, v, IREG[rd]);
    } else {
        sprintf(s, "%s%s,%s", co, IREG[rs2], IREG[rd]);
    }
}

void disas_jmpl(char *s, uint32_t op)
{
    int32_t v;
    uint32_t rs1, rs2, rd;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);

    if (rd == 0 && rs1 == 31 && v == 8)
        strcpy(s, "RET     ");
    else if (rd == 0 && rs1 == 15 && v == 8)
        strcpy(s, "RETL    ");
    else if (rd == 0) {
        strcpy(s, "JMP     ");
        rspido(&s[8], op);
    } else if (rd == 15) {
        strcpy(s, "CALL    ");
        rspido(&s[8], op);
    } else {
        strcpy(s, "JMPL    ");
        rspido(&s[8], op);
        strcat(s, ",");
        strcat(s, IREG[rd]);
    }
}

void disas_ticc(char *s, uint32_t op)
{
    strcpy(s, "T");
    strcat(s, ICOND[BIF(op, 29, 25)]);
    strcat(s, "  ");
    rspido(&s[strlen(s)], op);
}

void disas_shift(char *s, uint32_t op, char *co)
{
    uint32_t rs1, rs2, rd;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);

    if (BIK(op, 13))
        sprintf(s, "%s%s, %d,%s", co, IREG[rs1], rs2, IREG[rd]);
    else
        sprintf(s, "%s%s,%s,%s", co, IREG[rs1], IREG[rs2], IREG[rd]);
}

void disas_wrspr(char *s, uint32_t op, char *reg)
{
    int32_t v;
    uint32_t rs1, rs2;
    v = BIF(op, 12, 0);
    if (BIK(op, 12))
        v -= 1 << 13;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);

    if (BIK(op, 13))
        sprintf(s, "WR %s, %X,%s", IREG[rs1], v, reg);
    else
        sprintf(s, "WR %s, %s,%s", IREG[rs1], IREG[rs2], reg);
}

void disas_fpop1(char *s, uint32_t op)
{
    uint32_t rs1, rs2, rd, opf;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);
    opf = BIF(op, 13, 5);

    switch (opf) {
    case 0b011000100:         // FiTOs
        sprintf(s, "FiTOs   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011001000:         // FiTOd
        sprintf(s, "FiTOd   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011001100:         // FiTOq
        sprintf(s, "FiTOq   %s,%s", FREG[rs2], FREG[rd]);
        break;

    case 0b011010001:         // FsTOi
        sprintf(s, "FsTOi   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011010010:         // FdTOi
        sprintf(s, "FdTOi   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011010011:         // FqTOi
        sprintf(s, "FqTOi   %s,%s", FREG[rs2], FREG[rd]);
        break;

    case 0b011001001:         // FsTOd
        sprintf(s, "FsTOd   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011001101:         // FsTOq
        sprintf(s, "FsTOq   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011000110:         // FdTOs
        sprintf(s, "FdTOs   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011001110:         // FdTOq
        sprintf(s, "FdTOq   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011000111:         // FqTOs
        sprintf(s, "FqTOs   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b011001011:         // FqTOd
        sprintf(s, "FqTOd   %s,%s", FREG[rs2], FREG[rd]);
        break;

    case 0b000000001:         // FMOVs
        sprintf(s, "FMOVs   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b000000101:         // FNEGs
        sprintf(s, "FNEGs   %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b000001001:         // FABSs
        sprintf(s, "FABSs   %s,%s", FREG[rs2], FREG[rd]);
        break;

    case 0b000101001:         // FSQRTs
        sprintf(s, "FSQRTs  %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b000101010:         // FSQRTd
        sprintf(s, "FSQRTd  %s,%s", FREG[rs2], FREG[rd]);
        break;
    case 0b000101011:         // FSQRTq
        sprintf(s, "FSQRTq  %s,%s", FREG[rs2], FREG[rd]);
        break;

    case 0b001000001:         // FADDs
        sprintf(s, "FADDs   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001000010:         // FADDd
        sprintf(s, "FADDd   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001000011:         // FADDq
        sprintf(s, "FADDq   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001000101:         // FSUBs
        sprintf(s, "FSUBs   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001000110:         // FSUBd
        sprintf(s, "FSUBd   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001000111:         // FSUBq
        sprintf(s, "FSUBq   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;

    case 0b001001001:         // FMULs
        sprintf(s, "FMULs   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001001010:         // FMULd
        sprintf(s, "FMULd   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001001011:         // FMULq
        sprintf(s, "FMULq   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;

    case 0b001101001:         // FsMULd
        sprintf(s, "FsMULd  %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001101110:         // FdMULq
        sprintf(s, "FdMULq  %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;

    case 0b001001101:         // FDIVs
        sprintf(s, "FDIVs   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001001110:         // FDIVd
        sprintf(s, "FDIVd   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;
    case 0b001001111:         // FDIVq
        sprintf(s, "FDIVq   %s,%s,%s", FREG[rs1], FREG[rs2], FREG[rd]);
        break;

    default:
        strcpy(s, "FPop1 invalide");
    }
}

void disas_fpop2(char *s, uint32_t op)
{
    uint32_t rs1, rs2, rd, opf;
    rs1 = BIF(op, 18, 14);
    rs2 = BIF(op, 4, 0);
    rd = BIF(op, 29, 25);
    opf = BIF(op, 13, 5);

    switch (opf) {
    case 0b001010001:         // FCMPs
        sprintf(s, "FCMPs   %s,%s", FREG[rs1], FREG[rs2]);
        break;
    case 0b001010010:         // FCMPd
        sprintf(s, "FCMPd   %s,%s", FREG[rs1], FREG[rs2]);
        break;
    case 0b001010011:         // FCMPq
        sprintf(s, "FCMPq   %s,%s", FREG[rs1], FREG[rs2]);
        break;

    case 0b001010101:         // FCMPEs
        sprintf(s, "FCMPEs  %s,%s", FREG[rs1], FREG[rs2]);
        break;
    case 0b001010110:         // FCMPEd
        sprintf(s, "FCMPEd  %s,%s", FREG[rs1], FREG[rs2]);
        break;
    case 0b001010111:         // FCMPEq
        sprintf(s, "FCMPEq  %s,%s", FREG[rs1], FREG[rs2]);
        break;
    default:
        strcpy(s, "FPop2 invalide");
    }
}

void disas_invalide(char *s, uint32_t op)
{
    sprintf(s, "<INVALIDE : %X>", (int) op);
}

void disas_alu(char *s, uint32_t op, uint32_t pc)
{
    uint32_t rs1, rd, op3;
    rs1 = BIF(op, 18, 14);
    rd = BIF(op, 29, 25);
    op3 = BIF(op, 24, 19);

    switch (op3) {
    case 0b000000:            // ADD
        disas_arith(s, op, "ADD     ");
        break;

    case 0b000001:            // AND
        disas_arith(s, op, "AND     ");
        break;

    case 0b000010:            // OR
        if (rs1 != 0)
            disas_arith(s, op, "OR      ");
        else
            disas_mov(s, op, "MOV     ");
        break;

    case 0b000011:            // XOR
        disas_arith(s, op, "XOR     ");
        break;

    case 0b000100:            // SUB
        disas_arith(s, op, "SUB     ");
        break;

    case 0b000101:            // ANDN
        disas_arith(s, op, "ANDN    ");
        break;

    case 0b000110:            // ORN
        disas_arith(s, op, "ORN     ");
        break;

    case 0b000111:            // XNOR
        disas_arith(s, op, "XNOR    ");
        break;

    case 0b001000:            // ADDX
        disas_arith(s, op, "ADDX    ");
        break;

    case 0b001001:            // SparcV9 : Multiply
        disas_invalide(s, op);
        break;

    case 0b001010:            // UMUL
        disas_arith(s, op, "UMUL    ");
        break;

    case 0b001011:            // SMUL
        disas_arith(s, op, "SMUL    ");
        break;

    case 0b001100:            // SUBX
        disas_arith(s, op, "SUBX    ");
        break;

    case 0b001101:            // Sparc V9 : Divide
        disas_invalide(s, op);
        break;

    case 0b001110:            // UDIV
        disas_arith(s, op, "UDIV    ");
        break;

    case 0b001111:            // SDIV
        disas_arith(s, op, "SDIV    ");
        break;

    case 0b010000:            // ADDcc
        disas_arith(s, op, "ADDcc   ");
        break;

    case 0b010001:            // ANDcc
        disas_arith(s, op, "ANDcc   ");
        break;

    case 0b010010:            // ORcc
        disas_arith(s, op, "ORcc    ");
        break;

    case 0b010011:            // XORcc
        disas_arith(s, op, "XORcc   ");
        break;

    case 0b010100:            // SUBcc
        if (rd != 0)
            disas_arith(s, op, "SUBcc   ");
        else
            disas_comp(s, op, "CMPcc   ");
        break;

    case 0b010101:            // ANDNcc
        disas_arith(s, op, "ANDNcc  ");
        break;

    case 0b010110:            // ORNcc
        disas_arith(s, op, "ORNcc   ");
        break;

    case 0b010111:            // XNORcc
        disas_arith(s, op, "XNORcc  ");
        break;

    case 0b011000:            // ADDXcc
        disas_arith(s, op, "ADDXcc  ");
        break;

    case 0b011001:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b011010:            // UMULcc
        disas_arith(s, op, "UMULcc  ");
        break;

    case 0b011011:            // SMULcc
        disas_arith(s, op, "SMULcc  ");
        break;

    case 0b011100:            // SUBXcc
        disas_arith(s, op, "SUBXcc  ");
        break;

    case 0b011101:            // Sparc V8E : DIVScc
        disas_arith(s, op, "DIVScc  ");
        break;

    case 0b011110:            // UDIVcc
        disas_arith(s, op, "UDIVcc  ");
        break;

    case 0b011111:            // SDIVcc
        disas_arith(s, op, "SDIVcc  ");
        break;

    case 0b100000:            // TADDcc
        disas_arith(s, op, "TADDcc  ");
        break;

    case 0b100001:            // TSUBcc
        disas_arith(s, op, "TSUBcc  ");
        break;

    case 0b100010:            // TADDccTV
        disas_arith(s, op, "TADDccTV");
        break;

    case 0b100011:            // TSUBccTV
        disas_arith(s, op, "TSUBccTV");
        break;

    case 0b100100:            // MULScc : Multiply Step
        disas_arith(s, op, "MULScc  ");
        break;

    case 0b100101:            // SLL
        disas_shift(s, op, "SLL     ");
        break;

    case 0b100110:            // SRL
        disas_shift(s, op, "SRL     ");
        break;

    case 0b100111:            // SRA
        disas_shift(s, op, "SRA     ");
        break;

    case 0b101000:            // RDY
        sprintf(s, "RD %y,%s", IREG[rd]);
        break;

    case 0b101001:            // RDPSR (PRIV)
        sprintf(s, "RD %%psr,%s", IREG[rd]);
        break;

    case 0b101010:            // RDWIM (PRIV)
        sprintf(s, "RD %%wim,%s", IREG[rd]);
        break;

    case 0b101011:            // RDTBR (PRIV)      
        sprintf(s, "RD %%tbr,%s", IREG[rd]);
        break;

    case 0b101100:            // Sparc V9 : Move Integer Condition
        disas_invalide(s, op);
        break;

    case 0b101101:            // Sparc V9 : Signed Divide 64bits
        disas_invalide(s, op);
        break;

    case 0b101110:            // Sparc V9 : Population Count
        disas_invalide(s, op);
        break;

    case 0b101111:            // Sparc V9 : Move Integer Condition
        disas_invalide(s, op);
        break;

    case 0b110000:            // WRASR/WRY
        disas_wrspr(s, op, "%y");
        break;

    case 0b110001:            // WRPSR (PRIV)
        disas_wrspr(s, op, "%psr");
        break;

    case 0b110010:            // WRWIM (PRIV)
        disas_wrspr(s, op, "%wim");
        break;

    case 0b110011:            // WRTBR (PRIV)
        disas_wrspr(s, op, "%tbr");
        break;

    case 0b110100:            // FPOP1
        disas_fpop1(s, op);
        break;

    case 0b110101:            // FPOP2
        disas_fpop2(s, op);
        break;

    case 0b110110:            // CPOP1
        disas_invalide(s, op);  //,"CPOP1");
        break;

    case 0b110111:            // CPOP2
        disas_invalide(s, op);  //,"CPOP2");
        break;

    case 0b111000:            // JMPL : Jump And Link
        disas_jmpl(s, op);
        break;

    case 0b111001:            // RETT (PRIV)
        strcpy(s, "RETT    ");
        rspido(&s[8], op);
        break;

    case 0b111010:            // Ticc (B.27)
        disas_ticc(s, op);
        break;

    case 0b111011:            // IFLUSH
        strcpy(s, "IFLUSH  ");
        rspido(&s[8], op);
        break;

    case 0b111100:            // SAVE (B.20)
        disas_arith(s, op, "SAVE    ");
        break;

    case 0b111101:            // RESTORE (B.20)
        disas_arith(s, op, "RESTORE ");
        break;

    case 0b111110:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111111:            // Invalide
        disas_invalide(s, op);
        break;

    default:
        strcpy(s, "disas_alu : Erreur");
    }
}

void disas_lsu(char *s, uint32_t op, uint32_t pc)
{
    uint32_t rd, op3, asi;
    rd = BIF(op, 29, 25);
    op3 = BIF(op, 24, 19);
    asi = BIF(op, 12, 5);

    switch (op3) {
    case 0b000000:            // LD : Load Word
        strcpy(s, "LD      " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b000001:            // LDUB : Load Unsigned Byte
        strcpy(s, "LDUB    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b000010:            // LDUH : Load Unsigned Half Word
        strcpy(s, "LDUH    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b000011:            // LDD : Load DoubleWord
        strcpy(s, "LDD     " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b000100:            // ST
        strcpy(s, "ST      ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b000101:            // STB
        strcpy(s, "STB     ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b000110:            // STH
        strcpy(s, "STH     ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b000111:            // STD
        strcpy(s, "STD     ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b001000:            // SparcV9 : LDSW : Load Signed Word
        disas_invalide(s, op);
        break;

    case 0b001001:            // LDSB : Load Signed Byte
        strcpy(s, "LDSB    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b001010:            // LDSH : Load Signed Half Word
        strcpy(s, "LDSH    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b001011:            // SparcV9 : LDX : Load Extended Word : 64bits
        disas_invalide(s, op);
        break;

    case 0b001100:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b001101:            // LDSTUB : Atomic Load/Store Unsigned Byte
        strcpy(s, "LDSTUB  " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b001110:            // SparcV9 : STX : Store Extended Word : 64bits
        disas_invalide(s, op);
        break;

    case 0b001111:            // SWAP : Swap register with Memory
        strcpy(s, "SWAP    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, IREG[rd]);
        break;

    case 0b010000:            // LDA : Load Word from Alternate Space (PRIV)
        strcpy(s, "LDA     " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "] ");
        sprintf(&s[strlen(s)], "%2X,%s", asi, IREG[rd]);
        break;

    case 0b010001:            // LDUBA : Load Unsigned Byte from Alternate Space
        strcpy(s, "LDUBA   " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "] ");
        sprintf(&s[strlen(s)], "%2X,%s", asi, IREG[rd]);
        break;

    case 0b010010:            // LDUHA : Load Unsigned HalfWord from Alt. Space
        strcpy(s, "LDUHA   " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "] ");
        sprintf(&s[strlen(s)], "%2X,%s", asi, IREG[rd]);
        break;

    case 0b010011:            // LDDA : Load DoubleWord from Alternate Space (PRIV)
        strcpy(s, "LDDA    " "[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X,%s", asi, IREG[rd]);
        break;

    case 0b010100:            // STA : Store Word into Alternate Space (PRIV)
        strcpy(s, "STA     ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b010101:            // STBA : Store Byte into Alternate Space (PRIV)
        strcpy(s, "STBA    ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b010110:            // STHA : Store Half Word into Alternate Space (PRIV)
        strcpy(s, "STHA    ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b010111:            // STDA : Store DoubleWord into Alternate Space (PRIV)
        strcpy(s, "STDA    ");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b011000:            // SparcV9 : LDSWA : Load Signed Word into Alternate Space
        disas_invalide(s, op);
        break;

    case 0b011001:            // LDSBA : Load Signed Byte from Alternate Space (PRIV)
        strcpy(s, "LDSBA   " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "] ");
        sprintf(&s[strlen(s)], "%2X,%s", asi, IREG[rd]);
        break;

    case 0b011010:            // LDSHA : Load Signed Half Word from Alternate Space (PRIV)
        strcpy(s, "LDSHA   " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "] ");
        sprintf(&s[strlen(s)], "%2X,%s", asi, IREG[rd]);
        break;

    case 0b011011:            // SparcV9 : LDXA: Load Extended Word from Alternate Space : 64bit
        disas_invalide(s, op);
        break;

    case 0b011100:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b011101:            // LDSTUBA : Atomic Load/Store Unsigned Byte in Alt. Space (PRIV)
        strcpy(s, "LDSTUBA " "[");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b011110:            // SparcV9 : STXA : Store Extended Word fro Alternate Space : 64bits
        disas_invalide(s, op);
        break;

    case 0b011111:            // SWAPA : Swap register with memory in Alternate Space (PRIV)
        strcpy(s, "SWAPA   " "[");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b100000:            // LDF : Load Floating Point
        strcpy(s, "LDF     " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, FREG[rd]);
        break;

    case 0b100001:            // LDFSR : Load Floating Point State Register
        strcpy(s, "LDFSR   " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "], %fsr");
        break;

    case 0b100010:            // SparcV9 : LDQF : Load Quad Floating Point
        disas_invalide(s, op);
        break;

    case 0b100011:            // LDDF : Load Double Floating Point
        strcpy(s, "LDDF    " "[");
        rspido(&s[strlen(s)], op);
        strcat(s, "],");
        strcat(s, FREG[rd]);
        break;

    case 0b100100:            // STF : Store Floating Point
        strcpy(s, "STF     ");
        strcat(s, FREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b100101:            // STFSR : Store Floating Point State Register
        strcpy(s, "STFSR   %fsr ,[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b100110:            // STDFQ : Store Double Floating Point Queue (PRIV)
        strcpy(s, "STDFQ   %fq ,[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b100111:            // STDF : Store Double Floating Point
        strcpy(s, "STDF    ");
        strcat(s, FREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);
        strcat(s, "]");
        break;

    case 0b101000:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101001:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101010:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101011:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101100:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101101:            // SparcV9 : PREFETCH
        disas_invalide(s, op);
        break;

    case 0b101110:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b101111:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b110000:            // LDC : Load Coprocessor
        strcpy(s, "LDC     " " Coprocessor ?");
        break;

    case 0b110001:            // LDCSR : Load Coprocessor State Register
        strcpy(s, "LDCSR   " " Coprocessor ?");
        break;

    case 0b110010:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b110011:            // LDDC : Load Double Coprocessor
        strcpy(s, "LDDC    " " Coprocessor ?");
        break;

    case 0b110100:            // STC : Store Coprocessor
        strcpy(s, "STC     " " Coprocessor ?");
        break;

    case 0b110101:            // STCSR : Store Coprocessor State Register
        strcpy(s, "STCSR   " " Coprocessor ?");
        break;

    case 0b110110:            // STDCQ : Store Double Coprocessor Queue
        strcpy(s, "STDCQ   " " Coprocessor ?");
        break;

    case 0b110111:            // STDC : Store Double Coprocessor
        strcpy(s, "STDC    " " Coprocessor ?");
        break;

    case 0b111000:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111001:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111010:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111011:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111100:            // CASA Compare & Swap Atomic (V9+LEON)
        strcpy(s, "CASA   " "[");
        strcat(s, IREG[rd]);
        strcat(s, ",[");
        rspido(&s[strlen(s)], op);  // no [RS1+RS2] -> [RS1],RS2
        sprintf(&s[strlen(s)], "] %2X", asi);
        break;

    case 0b111101:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111110:            // Invalide
        disas_invalide(s, op);
        break;

    case 0b111111:            // Invalide
        disas_invalide(s, op);
        break;

    default:
        strcpy(s, "disas_lsu : Erreur");
    }
}

void disas_call(char *s, uint32_t op, uint32_t pc)
{
    uint32_t disp, v;
    disp = BIF(op, 29, 0);
    v = pc + disp * 4;
    sprintf(s, "CALL    %08X <%s>", (int) v, symbol(v));
}

void disas_bicc(char *s, uint32_t op, uint32_t pc)
{
    uint32_t v, cnd;
    int imm;
    cnd = BIF(op, 29, 25);
    imm = BIF(op, 21, 0);
    if (BIK(op, 21))
        imm = imm - (1 << 22);
    v = pc + imm * 4;
    sprintf(s, "B%s %08X", ICOND[cnd], (int) v);
}

void disas_fbfcc(char *s, uint32_t op, uint32_t pc)
{
    uint32_t v, cnd;
    int imm;
    cnd = BIF(op, 29, 25);
    imm = BIF(op, 21, 0);
    if (BIK(op, 21))
        imm = imm - (1 << 22);
    v = pc + imm * 4;
    sprintf(s, "FB%s %08X", FCOND[cnd], (int) v);
}

void pad(char *s)
{
    int i;
    for (i = strlen(s); i < 42; i++)
        s[i] = ' ';
    s[42] = 0;
}

void disassemble(char *s, uint32_t op, uint32_t pc)
{
    uint32_t opop, rd, op2, imm;
    opop = BIF(op, 31, 30);
    rd = BIF(op, 29, 25);
    op2 = BIF(op, 24, 22);
    imm = BIF(op, 21, 0);

    switch (opop) {
    case 0:
        switch (op2) {
        case 0:                // UNIMP : Unimplemented instruction
            sprintf(s, "UNIMP   %08X", op);
            break;
        case 1:                // SparcV9 BPcc : Integer Conditional Branch with Prediction
            disas_invalide(s, op);
            break;

        case 2:                // Bicc : Integer Conditional Branch
            disas_bicc(s, op, pc);
            break;

        case 3:                // SparcV9 : BPr
            disas_invalide(s, op);
            break;

        case 4:                // SETHI : Set High 22 bits of register
            if (imm == 0 && rd == 0)
                strcpy(s, "NOP     ");  //NOP = SETHI 0,g0
            else
                sprintf(s, "SETHI   x%08X,%s", imm << 10, IREG[rd]);
            break;

        case 5:                // SparcV9 FBPfcc : Floating Point Cond. Branch with Prediction
            disas_invalide(s, op);
            break;

        case 6:                // FBfcc : Floating Point Conditional Branch
            disas_fbfcc(s, op, pc);
            break;

        case 7:                // CBccc : Coprocessor Conditional Branch
            strcpy(s, "CBccc   ");
            break;
        default:
            strcpy(s, "xxx");
            break;
        }
        break;
    case 1:                    // CALL
        disas_call(s, op, pc);
        break;
    case 2:                    // Arith/Logic/FPU
        disas_alu(s, op, pc);
        break;
    case 3:                    // Load/Store
        disas_lsu(s, op, pc);
        break;
    default:
        strcpy(s, "xxx");
        break;
    }
    pad(s);

}


const char *TRAPS[] = {
    /*00 */ "TT_RESET",
    /*01 */ "TT_INSTRUCTION_ACCESS_EXCEPTION",
    /*02 */ "TT_ILLEGAL_INSTRUCTION",
    /*03 */ "TT_PRIVILEGED_INSTRUCTION",
    /*04 */ "TT_FP_DISABLED",
    /*05 */ "TT_WINDOW_OVERFLOW",
    /*06 */ "TT_WINDOW_UNDERFLOW",
    /*07 */ "TT_MEM_ADDRESS_NOT_ALIGNED",
    /*08 */ "TT_FP_EXCEPTION",
    /*09 */ "TT_DATA_ACCESS_EXCEPTION",
    /*0A */ "TT_TAG_OVERFLOW",
    /*0B */ "TT_WATCHPOINT_DETECTED",
    /*0C */ "TT_??? 0C",
    /*0D */ "TT_??? 0D",
    /*0E */ "TT_??? 0E",
    /*0F */ "TT_??? 0F",
    /*10 */ "TT_??? 10",
    /*11 */ "TT_INTERRUPT_LEVEL_1",
    /*12 */ "TT_INTERRUPT_LEVEL_2",
    /*13 */ "TT_INTERRUPT_LEVEL_3",
    /*14 */ "TT_INTERRUPT_LEVEL_4",
    /*15 */ "TT_INTERRUPT_LEVEL_5",
    /*16 */ "TT_INTERRUPT_LEVEL_6",
    /*17 */ "TT_INTERRUPT_LEVEL_7",
    /*18 */ "TT_INTERRUPT_LEVEL_8",
    /*19 */ "TT_INTERRUPT_LEVEL_9",
    /*1A */ "TT_INTERRUPT_LEVEL_10",
    /*1B */ "TT_INTERRUPT_LEVEL_11",
    /*1C */ "TT_INTERRUPT_LEVEL_12",
    /*1D */ "TT_INTERRUPT_LEVEL_13",
    /*1E */ "TT_INTERRUPT_LEVEL_14",
    /*1F */ "TT_INTERRUPT_LEVEL_15",
    /*20 */ "TT_R_REGISTER_ACCESS_ERROR",
    /*21 */ "TT_INSTRUCTION_ACCESS_ERROR",
    /*22 */ "TT_??? 22",
    /*23 */ "TT_??? 23",
    /*24 */ "TT_CP_DISABLED",
    /*25 */ "TT_UNIMPLEMENTED_FLUSH",
    /*26 */ "TT_??? 26",
    /*27 */ "TT_??? 27",
    /*28 */ "TT_CP_EXCEPTION",
    /*29 */ "TT_DATA_ACCESS_ERROR",
    /*2A */ "TT_DIVISION_BY_ZERO",
    /*2B */ "TT_DATA_STORE_ERROR",
    /*2C */ "TT_DATA_ACCESS_MMU_MISS",
    /*2D */ "TT_??? 2D",
    /*2E */ "TT_??? 2E",
    /*2F */ "TT_??? 2F",
    /*30 */ "TT_??? 30",
    /*31 */ "TT_??? 31",
    /*32 */ "TT_??? 32",
    /*33 */ "TT_??? 33",
    /*34 */ "TT_??? 34",
    /*35 */ "TT_??? 35",
    /*36 */ "TT_??? 36",
    /*37 */ "TT_??? 37",
    /*38 */ "TT_??? 38",
    /*39 */ "TT_??? 39",
    /*3A */ "TT_??? 3A",
    /*3B */ "TT_??? 3B",
    /*3C */ "TT_INSTRUCTION_ACCESS_MMU_MISS",
    /*3D */ "TT_??? 3D",
    /*3E */ "TT_??? 3E",
    /*3F */ "TT_??? 3F"
};
