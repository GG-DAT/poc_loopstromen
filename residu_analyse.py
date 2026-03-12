# -*- coding: utf-8 -*-
"""
Created on Tue Mar  4 16:36:28 2025

@author: tthomas
"""

import numpy as np
from scipy.spatial import cKDTree
import geopandas as gpd
import psycopg2

                
def getprovincies():
    provincies = {}

    # DATA NIET BESCHIKBAAR

    return provincies


def getarea_province(provincie):
    area = []

    # DATA NIET BESCHIKBAAR

    return area
    
def get_station_nodes():
    stationxys = []

    # DATA NIET BESCHIKBAAR

    return stationxys    


def gettripgen(provafk):

    # get network
    linknodes, linktypes, linklengths, linkgeom = {}, {}, {}, {}
    nodexys, nwalknodes, linkfwalk = {}, {}, {}

    # DATA NIET BESCHIKBAAR

    return linknodes,linktypes,linklengths,linkfwalk,linkgeom,nodexys,nwalknodes

def getprop(provafk,qprop):

    # DATA NIET BESCHIKBAAR

    return qprop


def getmod(provafk,qmod):
    
    # DATA NIET BESCHIKBAAR

    return qmod


def getturns(provafk,nodeturns):
    
   # DATA NIET BESCHIKBAAR
 
    return nodeturns


def get_nodelinks(linknodes_in):

    nodelinks_out = {}

    # DATA NIET BESCHIKBAAR
    
    return nodelinks_out


def mainlinknodes(linknodes,nodelinks,mainnodes,nodexys):

    # links en lengtes van segmenten tussen kruispunten / dead ends 
    mlinknodes, mlinklinks, links_to_mlinks = {}, {}, {}, {}

    # DATA NIET BESCHIKBAAR

    return mlinknodes,mlinklinks,links_to_mlinks


def getmlinklengths(links_to_mlinks,linklengths):
    mlinklengths = {}

    # DATA NIET BESCHIKBAAR

    return mlinklengths        


def dxylinks(nodelinks,linknodes,linkgeom):

    nodedxys = {}
    for node in nodelinks:
        nodedxys[node] = {}
        for link in nodelinks[node]:
            xy = linkgeom[link].split('(')[1][:-1].split(',')
            if linknodes[link][0] == node:
                xy1 = xy[0].split(' ')
                xy2 = xy[1].split(' ')
            if linknodes[link][1] == node:
                xy1 = xy[-1].split(' ')
                xy2 = xy[-2].split(' ')
            nodedxys[node][link] = np.array([float(xy2[0])-float(xy1[0]),
                                             float(xy2[1])-float(xy1[1])])
            hlength = np.sqrt(nodedxys[node][link][0]**2+nodedxys[node][link][1]**2)
            nodedxys[node][link] = nodedxys[node][link]/hlength

    return nodedxys


def getlinkpairs(nodedxys,mnodelinks,links_to_mlinks):

    mnodepairs, mlinkmlinks = {}, {}
    for link in links_to_mlinks:
        mlinkmlinks[links_to_mlinks[link]] = []        

    for node in mnodelinks:
        mnodepairs[node] = {}
        hmatch = {}
        for link in nodedxys[node]:
            for link2 in nodedxys[node]:
                if link < link2:
                    hmatch[link,link2] = 0
        for link in nodedxys[node]:
            linkmatch = 0
            inprod_min = -1/np.sqrt(2)
            for link2 in nodedxys[node]:
                if link != link2:
                    inprod = (nodedxys[node][link][0]*nodedxys[node][link2][0]+
                              nodedxys[node][link][1]*nodedxys[node][link2][1])
                    if inprod < inprod_min:
                        linkmatch = link2
                        inprod_min = inprod
            if linkmatch > 0:
                link1, link2 = link, linkmatch
                if link2 < link1:
                    link1, link2 = linkmatch, link                     
                hmatch[link1,link2] += 1
        for link1,link2 in hmatch:
            if hmatch[link1,link2] == 2:
                mnodepairs[node][link1] = link2
                mnodepairs[node][link2] = link1
    for node in mnodelinks:
        for link in mnodepairs[node]:
            link2 = mnodepairs[node][link]
            mlinkmlinks[links_to_mlinks[link]].append(links_to_mlinks[link2])

    return mnodepairs,mlinkmlinks  


def getsegments(mlinkmlinks,mlinklengths,links_to_mlinks,linklengths):

    segments, port = {}, {}
    for mlink in mlinkmlinks:
        port[mlink] = 0

    for mlink in mlinkmlinks:
        if port[mlink] == 0 and len(mlinkmlinks[mlink]) == 1:
            endseg = False
            mlink2 = mlink
            port[mlink2] = 1
            segments[mlink] = [mlink]
            while not endseg:
                endseg = True
                for mlink3 in mlinkmlinks[mlink2]:
                    if port[mlink3] == 0:
                        endseg = False
                        port[mlink3] = 1
                        segments[mlink].append(mlink3)
                        break
                mlink2 = mlink3

    for mlink in mlinkmlinks:
        if port[mlink] == 0:
            segments[mlink] = [mlink]

    segmentlengths = {}
    for segment in segments:
        segmentlengths[segment] = 0
        for mlink in segments[segment]:
            segmentlengths[segment] += mlinklengths[mlink]

    mlinkseglengths = {}                            
    for segment in segments:
        for mlink in segments[segment]:
            mlinkseglengths[mlink] = segmentlengths[segment]

    linkseglengths = {}
    # for isolated links
    for link in linklengths:
        linkseglengths[link] = linklengths[link]
    # link attribute length segments 
    for link in links_to_mlinks:
        linkseglengths[link] = mlinkseglengths[links_to_mlinks[link]]

    return linkseglengths, segments


def get_gridtrips(nodexys,nwalknodes,gridsize):    

    # nodes and trips to arrays
    xys, nwalk = [], []
    for node in nodexys:
        xys.append(nodexys[node])
        nwalk.append(nwalknodes[node])
    xys, nwalk = np.array(xys), np.array(nwalk)

    # xy to grid coordinates
    imin, imax = int(np.min(xys[:,0])/gridsize), int(np.max(xys[:,0])/gridsize)
    jmin, jmax = int(np.min(xys[:,1])/gridsize), int(np.max(xys[:,1])/gridsize)
    iis = np.intc(xys[:,0]/gridsize)-imin
    jjs = np.intc(xys[:,1]/gridsize)-jmin 
    nni = imax - imin + 1 
    nnj = jmax - jmin + 1

    # walk trips per gridcell
    nwalkgrid = np.zeros((nni,nnj))
    for i in range(len(nwalk)):
        nwalkgrid[iis[i],jjs[i]] += nwalk[i]

    return nwalkgrid, nni, nnj, imin, jmin


def gravity_directions(nwalkgrid,nni,nnj,gridsize,d_avg,feucl):

    dmax_eucl = 2*d_avg/feucl
    nmax =  int(round(dmax_eucl/gridsize))
    ijdists, ijdirs = {}, {}
    iis = -nmax+np.array(range(2*nmax+1))

    nwalkdirection = np.zeros((nni,nnj,4,2))
    for i in iis:
        for j in iis:
            hdist = np.sqrt(i**2+j**2)
            if  hdist <= nmax and (i != 0 or j != 0):
                ijdists[i,j] = hdist
                ijdirs[i,j] = 0
                if i > 0 and abs(i) > abs(j):
                    ijdirs[i,j] = 1
                if j < 0 and abs(j) >= abs(i):
                    ijdirs[i,j] = 2
                if i < 0 and abs(i) > abs(j):
                    ijdirs[i,j] = 3

    for i,j in ijdists:
        dscale = feucl*gridsize*ijdists[i,j]/d_avg
        # exponentieel
        addgrav = nwalkgrid[nmax+i:nni-nmax+i,nmax+j:nnj-nmax+j]*np.exp(-dscale)
        # log-normaal
        #dscale = dscale + 0.001
        #addgrav = nwalkgrid[nmax+i:nni-nmax+i,nmax+j:nnj-nmax+j]*0.5*np.exp(-(np.log(dscale))**2)/dscale        
        nwalkdirection[nmax:-nmax,nmax:-nmax,ijdirs[i,j],0] += addgrav*i/ijdists[i,j]
        nwalkdirection[nmax:-nmax,nmax:-nmax,ijdirs[i,j],1] += addgrav*j/ijdists[i,j]

    return nwalkdirection
    


    
    


if __name__ == '__main__':


    path_volumes_out = 'data/volumes.npy'
    path_provincies_out = 'data/provincies.npy'
    
    path_groen_in = 'data/'
    
    gridsize = 100          # size of gridcells
    l0, l1 = 50, 300        # factoren voor gewichten lengten strings w = (1 - exp(-(l+l0)/l1))
    d_avg = 1000            # gemiddelde loopafstand
    feucl = 1.3             # gemiddelde ratio trip afstand vs. hemelsbreed

    portwalk, fwalk, tripsegs, tripsegs_nodes = [], [], [], []
    provarr, linksarr, qmodel, qbasis = [], [], [], []
    breedte, groen, water = [], [], []

    stationxys = get_station_nodes()

    iprov = 0
    provincies = getprovincies() 
    print(provincies)
    provincies_out = []
    provincies_list = ['Utrecht']
    for provincie in provincies:
        
        provafk = provincies[provincie]
        print(provincie,provafk)

        print('lees in intensiteiten')
        linknodes,linktypes,linklengths,linkfwalk,linkgeom,nodexys,nwalknodes = gettripgen(provafk)
        nodelinks = get_nodelinks(linknodes)
        qprop, qmod = {}, {}
        for link in linknodes:
            qprop[link] = 0
            qmod[link] = 0
        qprop = getprop(provafk,qprop)
        qmod = getmod(provafk,qmod)


        print('lees in groen, water en wegbreedte')
        file_groen = provincie.lower()+'_loopnetwerk_enriched_final.gpkg'
        if provincie == 'Fryslân':
            file_groen = 'fryslan_loopnetwerk_enriched_final.gpkg'
        gdf_groen = gpd.read_file(path_groen_in+file_groen)
        gdf_groen = gdf_groen.explode(index_parts=False)

        # Extract Coordinate List from Geometry
        groen_prov, water_prov, breedte_prov, linknodes_prov = {}, {}, {}, {}        
        xys = gdf_groen.apply(lambda x: [y for y in x['geometry'].coords], axis=1).to_list()
        hlinks, hbreedte = list(gdf_groen['link']), list(gdf_groen['wegbreedte'])
        hgroen, hwater = list(gdf_groen['veg_per_100m']), list(gdf_groen['water_type'])
        for i in range(len(hlinks)):
            groen_prov[int(hlinks[i])] = float(hgroen[i])
            water_prov[int(hlinks[i])] = 0
            if hwater[i] is not None:
                water_prov[int(hlinks[i])] = 1
            breedte_prov[int(hlinks[i])] = 0
            if hbreedte[i] is not None and hbreedte[i] != 'onbekend':            
                breedte_prov[int(hlinks[i])] = float(hbreedte[i])
            xy1 = (int(round(xys[i][0][0]*100))/100,int(round(xys[i][0][1]*100))/100)            
            xy2 = (int(round(xys[i][-1][0]*100))/100,int(round(xys[i][-1][1]*100))/100)            
            linknodes_prov[int(hlinks[i])] = [xy1,xy2]
          

        print('koppel algeheel loopnetwerk aan model netwerk')              
        mainnodes = {}    
        for node in nodexys:
            mainnodes[nodexys[node]] = 0
        for link in linknodes_prov:
            mainnodes[linknodes_prov[link][0]] = 1
            mainnodes[linknodes_prov[link][1]] = 1
                
        mlinknodes,mlinklinks,links_to_mlinks = mainlinknodes(linknodes,nodelinks,mainnodes,nodexys)

        nodepairs_prov = {}
        for link in mlinknodes:
            xy1 = nodexys[mlinknodes[link][0]]
            xy2 = nodexys[mlinknodes[link][1]]
            nodepairs_prov[xy1,xy2] = 0
        for link in linknodes_prov:
            nodepairs_prov[linknodes_prov[link][0],linknodes_prov[link][1]] = link
            nodepairs_prov[linknodes_prov[link][1],linknodes_prov[link][0]] = link

        nn1, nn2 = 0, 0
        links_to_groenlinks = {}
        for link in linknodes:
            links_to_groenlinks[link] = 0
        for link in mlinknodes:
            xy1 = nodexys[mlinknodes[link][0]]
            xy2 = nodexys[mlinknodes[link][1]]
            groenlink = nodepairs_prov[xy1,xy2]
            for link2 in mlinklinks[link]:
                links_to_groenlinks[link2] = groenlink
        
        print('station distances')
        # nodes and coordinates in arrays
        nodesport = {}
        nodes, xys = [], []
        for node in nodexys:
            nodes.append(node)
            xys.append(nodexys[node])
            nodesport[node] = 1
        nodes, xys = np.array(nodes), np.array(xys)
        
        # distances from nodes to station nodes; select nodes with distances < 20 m and set tripgen = 0
        ckd_tree = cKDTree(stationxys)
        dist, idx = ckd_tree.query(xys,k=1)
        hindex = np.where(dist<20)[0]
        for i in hindex:
            nodesport[nodes[i]] = 0
            nwalknodes[nodes[i]] = 0

    
        print('richtingen')
        nodedxys = dxylinks(nodelinks,linknodes,linkgeom)
        print('segmenten')
        for node in nodexys:
            mainnodes[nodexys[node]] = 0
        mlinknodes,mlinklinks,links_to_mlinks = mainlinknodes(linknodes,nodelinks,mainnodes,nodexys)
        mnodelinks = get_nodelinks(mlinknodes)
        mlinklengths = getmlinklengths(links_to_mlinks,linklengths)
        print('linkparen en strings')
        mnodepairs,mlinkmlinks = getlinkpairs(nodedxys,mnodelinks,links_to_mlinks)
        linkseglengths,segments = getsegments(mlinkmlinks,mlinklengths,links_to_mlinks,linklengths)
        linksegtrips, nodesegtrips, linklinksegtrips = {}, {}, {}
        for node in mnodelinks:
            nodesegtrips[node] = 0
        for segment in segments:
            hnodes, hlinks = [], []
            for mlink in segments[segment]:
                for link in mlinklinks[mlink]:
                    hlinks.append(link)
                    for node in linknodes[link]:
                        hnodes.append(node)
            hnodes = list(set(hnodes))
            hntrip = 0
            for node in hnodes:
                hntrip += nwalknodes[node]
            for link in hlinks:
                linksegtrips[link] = hntrip

        # put maximum linksegtrips on node
        for node in mnodelinks:
            for link in nodelinks[node]:
                if linksegtrips[link] > nodesegtrips[node]:
                    nodesegtrips[node] = linksegtrips[link]

        # put maximum nodesegtrips back on links
        for mlink in mlinklinks:
            linksegtrip = max(nodesegtrips[mlinknodes[mlink][0]],nodesegtrips[mlinknodes[mlink][1]])
            for link in mlinklinks[mlink]:
                linklinksegtrips[link] = linksegtrip
     
        for link in linktypes:
            if (qmod[link] + qprop[link] > 0 and 
                nodesport[linknodes[link][0]] * nodesport[linknodes[link][1]] == 1):
                pwalk = 0
                if linktypes[link] == 'pedestrian':
                    pwalk = 1
                portwalk.append(pwalk)
                fwalk.append(linkfwalk[link])
                tripsegs.append(linksegtrips[link])
                tripsegs_nodes.append(linklinksegtrips[link])
                qmodel.append(qmod[link])
                qbasis.append(qprop[link])
                linksarr.append(link)
                provarr.append(iprov)

                hgroen, hwater, hbreedte = -1, -1, -1
                if links_to_groenlinks[link] > 0:
                    hgroen = groen_prov[links_to_groenlinks[link]]
                    hwater = water_prov[links_to_groenlinks[link]]
                    hbreedte = breedte_prov[links_to_groenlinks[link]]
                groen.append(hgroen)
                water.append(hwater)
                breedte.append(hbreedte)

        provincies_out.append(provincie)
        iprov += 1

    # Bepaal ratio's 
    provincies_out = np.array(provincies_out)
    provarr, linksarr = np.array(provarr), np.array(linksarr)
    qmodel, qbasis = np.array(qmodel), np.array(qbasis)
    portwalk, fwalk = np.array(portwalk), np.array(fwalk)
    tripsegs, tripsegs_nodes = np.array(tripsegs), np.array(tripsegs_nodes)
    groen, water, breedte = np.array(groen), np.array(water), np.array(breedte)

    
    print(np.mean(qmodel),np.mean(qbasis))
    fbin = [[0,0.2],[0.2,0.4],[0.4,0.6],[0.6,0.8],[0.8,1.0]]

#    print()
#    print('tripsegs')
#    nbin = 5
#    for i in range(len(fbin)):
#        hindex = np.where((fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#        ratio = np.mean(qmodel[hindex])/np.mean(qbasis[hindex])
#        x = np.log10(1+tripsegs)
#        fw, x, y1, y2,  = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex]
#        xs = np.argsort(x)
#        for k in range(nbin):
#            mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]]) # * ratio
#            #print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2)  
#        print()
#        for j in range(2):
#            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#            x = np.log10(1+tripsegs)
#            fw, x, y1, y2 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex]
#            xs = np.argsort(x)
#            for k in range(nbin):
#                mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]]) # * ratio
#                print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2)  
#            print()


#    print('tripsegs nodes')
#    for i in range(len(fbin)):
#        hindex = np.where((fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#        ratio = np.mean(qmodel[hindex])/np.mean(qbasis[hindex])
#        x = np.log10(1+tripsegs_nodes)
#        fw, x, y1, y2,  = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex]
#        xs = np.argsort(x)
#        for k in range(nbin):
#            mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#            my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]]) # * ratio
#            #print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2)  
#        print()
#        for j in range(2):
#            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#            x = np.log10(1+tripsegs_nodes)
#            fw, x, y1, y2 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex]
#            xs = np.argsort(x)
#            for k in range(nbin):
#                mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]]) # * ratio
#                print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2)  
#            print()



    # Correction on synthetic model values based on residual analysis
    mfwalk = [[0.15,0.28,0.47,0.68],[0.15,0.28,0.48,0.69]]
    r0 = [[1,0.85,0.55,0.35],[1,0.85,0.55,0.28]]
    h0 = [[0,0.05,0.10,0.10],[0,0.04,0.10,0.13]]
    x1 = [[500,500,500,1000],[500,500,500,1000]]
    h1 = [[0,0.25,0.50,0.50],[0,0.20,0.45,0.85]]
    mfwalk, r0, h0 = np.array(mfwalk), np.array(r0), np.array(h0)
    x1, h1 = np.array(x1), np.array(h1)
    r1 = r0 + h0*np.log10(x1)

    logx = np.log10(1+tripsegs)
    qnew = np.zeros(len(qbasis))

    fwalk_extra = np.zeros(len(fwalk))
    fwalk_extra[:] = fwalk[:]
    for j in range(2):
        hindex = np.where((portwalk==j)&(fwalk<=mfwalk[j,0]))[0]
        fwalk_extra[hindex] = mfwalk[j,0]+0.0001
        hindex = np.where((portwalk==j)&(fwalk>mfwalk[j,-1]))[0]
        fwalk_extra[hindex] = mfwalk[j,-1]
        for i in range(len(mfwalk[j])-1):
            hindex = np.where((portwalk==j)&(fwalk_extra>mfwalk[j,i])&(fwalk_extra<=mfwalk[j,i+1]))[0]
            logx1, logx2 = logx[hindex], logx[hindex]
            dlogx1 = np.where(logx1 > np.log10(x1[j,i]), logx1 - np.log10(x1[j,i]), 0)
            dlogx2 = np.where(logx2 > np.log10(x1[j,i+1]), logx2 - np.log10(x1[j,i+1]), 0)
            logx1 = np.where(logx1 <= np.log10(x1[j,i]), logx1, np.log10(x1[j,i])) 
            logx2 = np.where(logx2 <= np.log10(x1[j,i+1]), logx2, np.log10(x1[j,i+1]))
            ratio1 = r0[j,i]+h0[j,i]*logx1 + h1[j,i]*dlogx1
            ratio2 = r0[j,i+1]+h0[j,i+1]*logx2 + h1[j,i+1]*dlogx2
            w2 = (fwalk_extra[hindex] - mfwalk[j,i])/(mfwalk[j,i+1] - mfwalk[j,i])
            ratio = (1-w2)*ratio1 + w2*ratio2
            qnew[hindex] = ratio * qbasis[hindex]
    
    print(np.mean(qmodel),np.mean(qnew))
    fbin = [[0,0.2],[0.2,0.4],[0.4,0.6],[0.6,0.8],[0.8,1.0]]

    ratios_water = np.ones((len(fbin),2))
    ratios_water[1:3,0], ratios_water[1:3,1] = 0.97, 1.05
    ratios_water[3:,0], ratios_water[3:,1] = 0.95, 1.10
    qnew_water = np.zeros(len(qbasis))
    qnew_water[:] = qnew[:]
    for i in range(len(fbin)):
        for j in range(2):
            hindex = np.where((water==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
            qnew_water[hindex] = ratios_water[i,j] * qnew[hindex]


    print()
    print('tripsegs')
    nbin = 5
    for i in range(len(fbin)):
        for j in range(2):
            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
            x = np.log10(1+tripsegs)
            fw, x, y1, y2, y3 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex], qnew[hindex]
            xs = np.argsort(x)
            for k in range(nbin):
                mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my3 = np.mean(y3[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2,my1/my3)
            print(np.mean(qmodel[hindex]),np.mean(qbasis[hindex]),np.mean(qnew[hindex]))
            print(np.corrcoef(qmodel[hindex],qbasis[hindex])[0,1],np.corrcoef(qmodel[hindex],qnew[hindex])[0,1])
            print()


    print('tripsegs nodes')
    for i in range(len(fbin)):
        for j in range(2):
            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
            x = np.log10(1+tripsegs_nodes)
            fw, x, y1, y2, y3 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex], qnew[hindex]
            xs = np.argsort(x)
            for k in range(nbin):
                mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                my3 = np.mean(y3[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
                print(str(int(round(mfw*100))/100),int(len(x)/nbin),int(round(10**mx)),int(round(my1)),my1/my2,my1/my3)      
            print()
        
#    print()
#    print('groen')
#    gbin = [0,10,20,30,40,1000000]
#    for i in range(len(fbin)):
#        for j in range(2):
#            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#            x = groen
#            fw, x, y1, y2, y3 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex], qnew[hindex]
#            for k in range(len(gbin)-1):
#                hindex2 = np.where((x>gbin[k]) & (x<=gbin[k+1]))[0]
#                mfw = np.mean(fw[hindex2])
#                mx = np.mean(x[hindex2])
#                my1 = np.mean(y1[hindex2])
#                my2 = np.mean(y2[hindex2])
#                my3 = np.mean(y3[hindex2])
#                print(str(int(round(mfw*100))/100),len(hindex2),mx,int(round(my1)),my1/my2,my1/my3)
#            print(np.mean(qmodel[hindex]),np.mean(qbasis[hindex]),np.mean(qnew[hindex]))
#            print(np.corrcoef(qmodel[hindex],qbasis[hindex])[0,1],np.corrcoef(qmodel[hindex],qnew[hindex])[0,1])
#            print()


    print()
    print('water')
    for i in range(len(fbin)):
        for j in range(2):
            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
            x = water
            fw, x, y1, y2, y3 = fwalk[hindex], x[hindex], qmodel[hindex], qnew[hindex], qnew_water[hindex]
            for k in range(2):
                hindex2 = np.where(x == k)[0]
                mfw = np.mean(fw[hindex2])
                mx = np.mean(x[hindex2])
                my1 = np.mean(y1[hindex2])
                my2 = np.mean(y2[hindex2])
                my3 = np.mean(y3[hindex2])
                print(str(int(round(mfw*100))/100),len(hindex2),mx,int(round(my1)),my1/my2,my1/my3)
            print(np.mean(qmodel[hindex]),np.mean(qnew[hindex]),np.mean(qnew_water[hindex]))
            print(np.corrcoef(qmodel[hindex],qnew[hindex])[0,1],np.corrcoef(qmodel[hindex],qnew_water[hindex])[0,1])
            print()


    
#    print()
#    print('wegbreedte')
#    nbin = 5
#    avg_breedte = np.mean(breedte)
#    breedte = np.where(breedte > 0, breedte, avg_breedte)
#    for i in range(len(fbin)):
#        for j in range(2):
#            hindex = np.where((portwalk==j)&(fwalk>fbin[i][0])&(fwalk<=fbin[i][1]))[0]
#            x = breedte
#            fw, x, y1, y2, y3 = fwalk[hindex], x[hindex], qmodel[hindex], qbasis[hindex], qnew[hindex]
#            xs = np.argsort(x)
#            for k in range(nbin):
#                mfw = np.mean(fw[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                mx = np.mean(x[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my1 = np.mean(y1[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my2 = np.mean(y2[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                my3 = np.mean(y3[xs[int(k*len(x)/nbin):int((k+1)*len(x)/nbin)]])
#                print(str(int(round(mfw*100))/100),int(len(x)/nbin),mx,int(round(my1)),my1/my2,my1/my3)
#            print(np.mean(qmodel[hindex]),np.mean(qbasis[hindex]),np.mean(qnew[hindex]))
#            print(np.corrcoef(qmodel[hindex],qbasis[hindex])[0,1],np.corrcoef(qmodel[hindex],qnew[hindex])[0,1])
#            print()


    print(np.corrcoef(qmodel,qbasis)[0,1],np.corrcoef(qmodel,qnew)[0,1],np.corrcoef(qmodel,qnew_water)[0,1])

    
#    volumes_out = np.zeros((len(qbasis),5),dtype=int)
#    volumes_out[:,0] = provarr
#    volumes_out[:,1] = linksarr
#    volumes_out[:,2] = np.rint(qmodel)
#    volumes_out[:,3] = np.rint(qbasis)
#    volumes_out[:,4] = np.rint(qnew)
#    
#    np.save(path_volumes_out, volumes_out)    
#    np.save(path_provincies_out, provincies_out)    
