#!/bin/bash
set -eux

OUTDIR=md
NATIVE=alanine-dipeptide.pdb
EM_NATIVE=em.pdb
FORCEFIELD=amber99
WATERMODEL=tip3p
DISTANCE=1.2
ADD_NACL=false
IGNORE_H=true

cd $(dirname "${BASH_SOURCE[0]}")
mkdir -p $OUTDIR
cd $OUTDIR

# convert initial PDB:
gmx pdb2gmx -f ../$NATIVE -o start.gro $($IGNORE_H && echo -ignh) -ff $FORCEFIELD -water $WATERMODEL

# define simulation box:
gmx editconf -f start.gro -o box.gro -bt cubic -d $DISTANCE

# add solvent:
gmx solvate -cp box.gro -cs spc216.gro -o solvated.gro -p topol.top

# add ions:
if $ADD_NACL; then
gmx grompp -f ../em.mdp -c solvated.gro -p topol.top -o ions.tpr -maxwarn 1
echo SOL | gmx genion -s ions.tpr -o solvated.gro -p topol.top -pname NA -nname CL -neutral -conc 0.15
fi

# minimize energy:
gmx grompp -f ../em.mdp -c solvated.gro -p topol.top -o em.tpr
gmx mdrun -v -deffnm em

# save the energy-minimized state:
echo 1 | gmx trjconv -f em.gro -s em.tpr -o ../$EM_NATIVE

# equilibrate with NVT:
gmx grompp -f ../nvt.mdp -c em.gro -r em.gro -p topol.top -o nvt.tpr
gmx mdrun -v -deffnm nvt

# NPT equilibrate:
gmx grompp -f ../npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt -p topol.top -o npt.tpr
gmx mdrun -v -deffnm npt

# run the production MD:
gmx grompp -f ../md.mdp -c nvt.gro -p topol.top -o md.tpr
gmx mdrun -v -deffnm md

# correct trajectory:
echo 1 | gmx trjconv -f md.xtc -s md.tpr -pbc nojump -o md_nojump.xtc
echo 1 | gmx trjconv -f md.xtc -s md.tpr -pbc mol -o md_center.xtc
echo 1 | gmx trjconv -f md.xtc -s md.tpr -pbc mol -fit rot+trans -o md_fitted.xtc

# Ramachandran plot:
gmx rama -f md.xtc -s md.tpr -xvg none -o phi_psi.xvg